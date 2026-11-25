"""Opt-in regression tests for the Week 13 concurrency review."""

from __future__ import annotations

import os
import re
import secrets
import unittest
from contextlib import closing

import pyodbc

from tools.week13_verify import connect, select, source, steps
from webapp import create_app
from webapp.services import digest

DATABASE = os.environ.get("DB_LAB_WEEK13_DATABASE", "")
SERVER = os.environ.get("DB_LAB_TEST_SERVER", r"localhost\SQLEXPRESS")


@unittest.skipUnless(DATABASE, "Set DB_LAB_WEEK13_DATABASE to a disposable WebW13 database")
class Week13ReviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not re.fullmatch(r"TokenHubDB_v11_WebW13[A-Za-z0-9]{2,9}", DATABASE):
            raise ValueError("Expected a disposable WebW13 database")
        with closing(connect(SERVER, DATABASE)) as db:
            if not select(db, "SELECT SCHEMA_ID('w13lab') AS id;")[0]["id"]:
                select(db, source("init"))
            if not select(db, "SELECT OBJECT_ID('w13lab.Business','U') AS id;")[0]["id"]:
                select(db, source("business_fixture"))

    def test_provider_aliases_use_one_inventory_lock(self) -> None:
        with closing(connect(SERVER, DATABASE)) as db:
            for alias in ("Other", "other", "Óther "):
                with self.subTest(alias=alias):
                    select(db, "BEGIN TRAN;")
                    try:
                        select(db, "EXEC w12.usp_LockInventoryProvider ?;", alias)
                        modes = select(
                            db,
                            "SELECT APPLOCK_MODE('public','TokenHub.Inventory.Other','Transaction') "
                            "AS canonical,APPLOCK_MODE('public',CONCAT('TokenHub.Inventory.',?),"
                            "'Transaction') AS alias;",
                            alias,
                        )[0]
                        self.assertEqual(modes["canonical"], "Exclusive")
                        if alias != "Other":
                            self.assertEqual(modes["alias"], "NoLock")
                    finally:
                        select(db, "ROLLBACK;")

    def test_manual_stock_timeouts_do_not_commit_restock(self) -> None:
        for scenario, step, locked_product in (
            ("write_wait", "B1", 1),
            ("repeatable_read", "B1", 1),
            ("deadlock", "B1_ordered", 1),
            ("deadlock", "B1_ordered", 2),
        ):
            with (
                self.subTest(scenario=scenario, locked_product=locked_product),
                closing(connect(SERVER, DATABASE)) as a,
                closing(connect(SERVER, DATABASE)) as b,
            ):
                select(a, source("reset"))
                if locked_product == 1:
                    select(a, steps("write_wait", "A")["A1"])
                else:
                    select(a, steps("deadlock", "B")["B1_reverse"])
                select(b, "SET XACT_ABORT OFF; SET LOCK_TIMEOUT 100;")
                try:
                    with self.assertRaisesRegex(pyodbc.Error, r"\(1222\)"):
                        select(b, steps(scenario, "B")[step])
                    count = select(b, "SELECT @@TRANCOUNT AS n;")
                finally:
                    select(a, "IF @@TRANCOUNT>0 ROLLBACK;")
                    select(b, "IF @@TRANCOUNT>0 ROLLBACK;")
                state = select(a, source("state"))[0]
                self.assertEqual(count, [{"n": 0}])
                self.assertEqual((state["p"], state["q"]), (10, 8))
                self.assertEqual((state["restock_state"], state["actual"]), ("pending", None))

    def test_web_restock_conflict_precedes_driver_timeout(self) -> None:
        app = create_app(
            {
                "TESTING": True,
                "SECRET_KEY": secrets.token_hex(32),
                "DB_SERVER": SERVER,
                "DB_DATABASE": DATABASE,
                "DB_PREVIEW": True,
            }
        )
        client = app.test_client()
        token, csrf = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        with closing(connect(SERVER, DATABASE)) as db:
            fixture = select(db, "SELECT task_id,account_id FROM w13lab.Business;")[0]
            task = int(str(fixture["task_id"]))
            account = int(str(fixture["account_id"]))
            employee = select(
                db, "SELECT employee_id FROM dbo.Employees WHERE account='web_admin';"
            )[0]["employee_id"]
            select(db, "EXEC app.StartSession 'employee',?,?;", int(str(employee)), digest(token))
            snapshot_sql = """SELECT t.status,t.actual_amount,a.total_quota,i.current_quota,
 (SELECT COUNT(*) FROM dbo.InventoryLog WHERE account_id=t.account_id) log_count,
 (SELECT COUNT(*) FROM w11.InventoryAudit WHERE account_id=t.account_id) audit_count
FROM dbo.RestockTask t JOIN dbo.UpstreamAccount a ON a.account_id=t.account_id
JOIN dbo.Inventory i ON i.account_id=a.account_id WHERE t.task_id=? AND a.account_id=?;"""
            before = select(db, snapshot_sql, task, account)
            try:
                self.assertEqual(len(before), 1)
                self.assertEqual(before[0]["status"], "pending")
                with client.session_transaction() as session:
                    session.update(token=token, csrf=csrf)
                select(db, "BEGIN TRAN;")
                select(db, "EXEC w12.usp_LockInventoryProvider 'Other';")
                response = client.post(
                    f"/api/v1/restocks/{task}/complete",
                    json={"actual_amount": "5"},
                    headers={"X-CSRF-Token": csrf},
                )
            finally:
                select(db, "IF @@TRANCOUNT>0 ROLLBACK;")
                select(db, "EXEC app.EndSession ?;", digest(token))
            self.assertEqual(response.status_code, 409, response.json)
            self.assertEqual(response.json["code"], "INVENTORY_BUSY")
            self.assertEqual(select(db, snapshot_sql, task, account), before)
