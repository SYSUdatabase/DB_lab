"""Recent dashboard samples are bounded, repeatable and transactional."""

import os
import unittest
import uuid

import pyodbc

from tools.seed_dashboard_recent import SAMPLE_USER, seed, validate_database

DATABASE = os.environ.get("DB_LAB_DASHBOARD_SEED_DATABASE", "")


class RecentSeedBoundaryTests(unittest.TestCase):
    def test_refuses_non_web_database(self) -> None:
        for name in ("master", "TokenHubDB_v01_A", "TokenHubDB_v11_Web;DROP", ""):
            with self.subTest(name=name), self.assertRaises(ValueError):
                validate_database(name)
        validate_database("TokenHubDB_v11_WebR1113225642")


@unittest.skipUnless(DATABASE, "Set DB_LAB_DASHBOARD_SEED_DATABASE for rollback-only integration")
class RecentSeedSqlTests(unittest.TestCase):
    def setUp(self) -> None:
        validate_database(DATABASE)
        self.db = pyodbc.connect(
            f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER=localhost\\SQLEXPRESS;DATABASE={DATABASE};"
            "Trusted_Connection=yes;TrustServerCertificate=yes;",
            autocommit=False,
        )
        self.addCleanup(self.db.close)
        self.addCleanup(self.db.rollback)
        # Temporarily free reserved fixture names; rollback restores existing samples.
        tag = uuid.uuid4().hex
        self.db.execute(
            "UPDATE dbo.Users SET username=?,email=? WHERE username=?",
            "recent_test_" + tag,
            tag + "@sample.invalid",
            SAMPLE_USER,
        )
        self.db.execute(
            "UPDATE dbo.Products SET name=? WHERE name=N'Dashboard Recent Sample'",
            "Recent Test " + tag,
        )

    def test_all_days_repeat_and_accounting(self) -> None:
        result = seed(self.db)
        self.assertEqual(len(result["daily_orders"]), 14)
        self.assertTrue(all(1 <= row["order_count"] <= 4 for row in result["daily_orders"]))
        second = seed(self.db)
        self.assertEqual(second["inserted_orders"], 0)
        self.assertEqual(second["daily_orders"], result["daily_orders"])
        invalid = self.db.execute(
            "SELECT COUNT(*) FROM dbo.Orders o JOIN dbo.Users u ON u.user_id=o.user_id "
            "WHERE u.username=? AND (o.created_at<u.created_at OR "
            "o.total_amount<>(SELECT SUM(subtotal) FROM dbo.OrderDetails d WHERE d.order_id=o.order_id))",
            SAMPLE_USER,
        ).fetchval()
        self.assertEqual(invalid, 0)
        self.assertEqual(
            self.db.execute(
                "SELECT COUNT(*) FROM dbo.TokenBalances WHERE remaining_tokens<0"
            ).fetchval(),
            0,
        )

    def test_caller_rollback_removes_samples(self) -> None:
        before = self.db.execute("SELECT COUNT(*) FROM dbo.Orders").fetchval()
        seed(self.db)
        self.db.rollback()
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM dbo.Orders").fetchval(), before)

    def test_midway_failure_leaves_no_partial_rows(self) -> None:
        before = self.db.execute("SELECT COUNT(*) FROM dbo.Orders").fetchval()
        self.db.execute(
            "CREATE TRIGGER dbo.trg_RecentSeedTestFault ON dbo.Orders AFTER INSERT AS "
            "BEGIN IF EXISTS(SELECT 1 FROM inserted i JOIN dbo.Users u ON u.user_id=i.user_id "
            "WHERE u.username='dashboard_recent_sample') THROW 55890,'Injected sample failure',1; END"
        )
        with self.assertRaisesRegex(pyodbc.Error, "55890"):
            seed(self.db)
        self.db.rollback()
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM dbo.Orders").fetchval(), before)
        self.assertIsNone(
            self.db.execute("SELECT OBJECT_ID('dbo.trg_RecentSeedTestFault')").fetchval()
        )
