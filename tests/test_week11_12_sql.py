"""Week 11 triggers/window queries and week 12 recursion/transactions on a disposable Web database."""

from __future__ import annotations

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parents[1]
DATABASE = os.environ.get("DB_LAB_WEEK12_DATABASE", "")
SERVER = os.environ.get("DB_LAB_TEST_SERVER", r"localhost\SQLEXPRESS")


def connect() -> pyodbc.Connection:
    """Require deliberate selection of an isolated database with weeks 10–12 installed."""
    if not re.fullmatch(r"TokenHubDB_v11_Web[A-Za-z0-9_]+", DATABASE):
        raise ValueError("DB_LAB_WEEK12_DATABASE must name an isolated v11 Web database")
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};"
        "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;",
        autocommit=False,
        timeout=15,
    )


def run_script(path: str) -> str:
    """Run a course SQL script with sqlcmd; read its UTF-8 output file, not the console encoding."""
    with tempfile.TemporaryDirectory() as folder:
        output_file = Path(folder) / "output.txt"
        completed = subprocess.run(
            ["sqlcmd", "-S", SERVER, "-d", DATABASE, "-E", "-C", "-b", "-f", "65001", "-W"]
            + ["-v", "DatabaseName=" + DATABASE, "-i", str(ROOT / path), "-o", str(output_file)],
            capture_output=True,
            cwd=ROOT,
            timeout=600,
        )
        output = output_file.read_text(encoding="utf-8-sig") if output_file.exists() else ""
    if completed.returncode != 0:
        raise AssertionError(f"{path} exited {completed.returncode}:\n{output[-3000:]}")
    return output


class Week11And12SourceTests(unittest.TestCase):
    def test_triggers_handle_multiple_rows(self) -> None:
        source = (ROOT / "sql/week11/trigger.sql").read_text(encoding="utf-8")
        self.assertIn("FROM inserted i FULL OUTER JOIN deleted d", source)
        self.assertIn("@done TABLE", source)
        self.assertNotRegex(source, r"(?i)SELECT\s+@\w+\s*=\s*\w+\.\w+\s+FROM\s+inserted")

    def test_window_queries_cover_three_kinds(self) -> None:
        source = (ROOT / "sql/week11/window_query.sql").read_text(encoding="utf-8")
        for token in ("RANK() OVER", "DENSE_RANK() OVER", "ROW_NUMBER() OVER"):
            self.assertIn(token, source)
        self.assertIn("ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW", source)
        self.assertIn("ROWS BETWEEN 2 PRECEDING AND CURRENT ROW", source)

    def test_old_entries_delegate_to_week12_transactions(self) -> None:
        order = (ROOT / "sql/week12/order_transaction.sql").read_text(encoding="utf-8")
        restock = (ROOT / "sql/week12/restock_transaction.sql").read_text(encoding="utf-8")
        self.assertIn("EXEC w12.usp_CompleteOrder", order)
        self.assertIn("EXEC w12.usp_ReceiveRestock", restock)
        self.assertIn("WHERE order_id=@order_id AND status='pending'", order)
        self.assertIn("status IN ('pending','in_progress');\n  IF @@ROWCOUNT<>1", restock)

    def test_app_entries_set_actor_for_audit(self) -> None:
        for path in ("sql/week10/app_adapters.sql", "sql/app/week10.sql"):
            source = (ROOT / path).read_text(encoding="utf-8")
            self.assertIn("sp_set_session_context @key=N'tokenhub.actor'", source)


@unittest.skipUnless(
    DATABASE, "Set DB_LAB_WEEK12_DATABASE to an isolated database with weeks 10-12"
)
class Week11And12SqlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.db = connect()
        self.addCleanup(self.db.close)
        self.addCleanup(self.db.rollback)

    def test_trigger_script_cases_all_pass(self) -> None:
        output = run_script("sql/week11/test_trigger.sql")
        summary = re.search(r"SUMMARY\|(\d+)/(\d+)\|TRANCOUNT=0", output)
        self.assertIsNotNone(summary, output[-2000:])
        self.assertEqual(summary.group(1), summary.group(2))

    def test_transaction_script_cases_all_pass(self) -> None:
        output = run_script("sql/week12/test_transactions.sql")
        summary = re.search(r"SUMMARY\|(\d+)/(\d+)\|TRANCOUNT=0", output)
        self.assertIsNotNone(summary, output[-2000:])
        self.assertEqual(summary.group(1), summary.group(2))

    def test_read_only_scripts_run(self) -> None:
        self.assertIn("moving_avg_amount_3d", run_script("sql/week11/window_query.sql"))
        self.assertIn("全部Token套餐 > 文本对话模型", run_script("sql/week12/recursive_query.sql"))

    def test_descendants_for_each_node_kind(self) -> None:
        cursor = self.db.cursor()
        expected = {1: 9, 2: 5, 8: 1, 999: 0}
        for category_id, count in expected.items():
            with self.subTest(category_id=category_id):
                rows = cursor.execute(
                    "SELECT category_id,level,id_path FROM w12.fn_CategoryDescendants(?)",
                    category_id,
                ).fetchall()
                self.assertEqual(len(rows), count)
        levels = {
            row.category_id: (row.level, row.id_path)
            for row in cursor.execute("SELECT * FROM w12.fn_CategoryDescendants(1)").fetchall()
        }
        self.assertEqual(levels[8], (3, "/1/2/4/8/"))
        self.assertEqual(levels[7], (2, "/1/3/7/"))

    def test_category_cycle_is_rejected(self) -> None:
        cursor = self.db.cursor()
        with self.assertRaisesRegex(pyodbc.Error, r"\(54420\)"):
            cursor.execute("UPDATE w12.ProductCategories SET parent_id=8 WHERE category_id=2")
        self.db.rollback()
        parent = cursor.execute(
            "SELECT parent_id FROM w12.ProductCategories WHERE category_id=2"
        ).fetchval()
        self.assertEqual(parent, 1)


if __name__ == "__main__":
    unittest.main()
