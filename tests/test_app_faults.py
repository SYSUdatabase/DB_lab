"""Rollback-only injected SQL faults and an observed refund/usage locking race."""

from __future__ import annotations

import json
import os
import queue
import re
import threading
import time
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor

import pyodbc

from tests import test_app_sql as workflow

DATABASE = os.environ.get("DB_LAB_APP_DATABASE", "")
SERVER = os.environ.get("DB_LAB_TEST_SERVER", r"localhost\SQLEXPRESS")


def connect() -> pyodbc.Connection:
    if not re.fullmatch(r"TokenHubDB_v11_Web[A-Za-z0-9_]*", DATABASE):
        raise RuntimeError("Fault regressions require an explicitly selected isolated Web database")
    connection = pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};"
        "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;",
        autocommit=False,
    )
    connection.timeout = 12
    return connection


def snapshot(connection: pyodbc.Connection) -> dict[str, tuple[int, int | None]]:
    """Compare every table without reading or hashing credential columns."""
    selections = {
        "Users": "user_id,username,email,phone,status,created_at,updated_at",
        "Employees": "employee_id,name,role_id,account,hire_date,status",
        "UpstreamAccount": "account_id,provider,account_name,total_quota,used_quota,safety_threshold,status,expires_at,created_at,updated_at",
        "Sessions": "user_id,employee_id,expires_at,revoked_at",
        "ExceptionLog": "exception_id,exception_type,related_table,related_id,occurred_at,handled_by,handle_result,handled_at",
    }
    cursor = connection.cursor()
    tables = cursor.execute(
        "SELECT s.name,t.name FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id WHERE t.is_ms_shipped=0 ORDER BY s.name,t.name"
    ).fetchall()
    results: dict[str, tuple[int, int | None]] = {}
    for schema, table in tables:
        fields = selections.get(table, "*")
        row = cursor.execute(
            f"SELECT COUNT_BIG(*),CHECKSUM_AGG(BINARY_CHECKSUM({fields})) FROM [{schema}].[{table}]"
        ).fetchone()
        results[f"{schema}.{table}"] = (int(row[0]), row[1])
    cursor.close()
    return results


def execute(
    connection: pyodbc.Connection, token: bytes, operation: str, payload: dict[str, object]
) -> dict[str, object]:
    cursor = connection.cursor()
    try:
        cursor.execute("EXEC app.[Execute] ?,?,?", token, operation, json.dumps(payload))
        rows = cursor.fetchall()
        if len(rows) != 1 or cursor.nextset():
            raise AssertionError("SQL result envelope changed")
        return json.loads(rows[0][0])
    finally:
        cursor.close()


@unittest.skipUnless(
    bool(DATABASE),
    "Set DB_LAB_APP_DATABASE to an isolated Web database",
)
class AppSqlFaultTests(unittest.TestCase):
    api = workflow.AppSqlWorkflowTests.api

    def setUp(self) -> None:
        with connect() as baseline_connection:
            self.baseline = snapshot(baseline_connection)
            baseline_connection.rollback()
        workflow.AppSqlWorkflowTests.setUp(self)

    def inject(self, table: str, event: str, condition: str) -> None:
        # The trigger and flag exist only inside this test's uncommitted fixture unit.
        self.connection.cursor().execute(
            f"CREATE TRIGGER dbo.trg_AppInjectedFault ON dbo.{table} AFTER {event} AS "
            "BEGIN SET NOCOUNT ON; "
            f"IF SESSION_CONTEXT(N'app_test_fault')=N'enabled' AND ({condition}) "
            "THROW 55971,'Injected late-operation failure',1; END;"
        )
        self.connection.cursor().execute(
            "EXEC sys.sp_set_session_context @key=N'app_test_fault',@value=N'enabled'"
        )

    def assert_rolled_back(
        self, operation: str, payload: dict[str, object], role: str = "customer"
    ) -> None:
        with self.assertRaisesRegex(pyodbc.Error, "55971"):
            self.api(role, operation, payload)
        cursor = self.connection.cursor()
        # The driver starts a fresh implicit transaction for this assertion SELECT.
        self.assertNotEqual(cursor.execute("SELECT XACT_STATE()").fetchone()[0], -1)
        self.assertEqual(
            cursor.execute(
                "SELECT COUNT(*) FROM sys.triggers WHERE name='trg_AppInjectedFault'"
            ).fetchone()[0],
            0,
        )
        self.assertEqual(
            cursor.execute(
                "SELECT COUNT(*) FROM dbo.Users WHERE user_id=?", self.user_id
            ).fetchone()[0],
            0,
        )
        self.assertEqual(snapshot(self.connection), self.baseline)
        cursor.execute("EXEC sys.sp_set_session_context @key=N'app_test_fault',@value=NULL")

    def draft(self) -> dict[str, object]:
        return self.api(
            "customer", "orders.create", {"items": [{"product_id": self.product_id, "quantity": 1}]}
        )

    def test_payment_failure_after_balance_header_and_lot_writes(self) -> None:
        order = self.draft()
        self.inject("OrderTokenLots", "INSERT", "EXISTS(SELECT 1 FROM inserted)")
        self.assert_rolled_back("orders.pay", order)

    def test_usage_failure_after_balance_account_inventory_and_log_writes(self) -> None:
        self.api("customer", "orders.pay", self.draft())
        self.inject(
            "InventoryLog",
            "INSERT",
            "EXISTS(SELECT 1 FROM inserted WHERE change_type='consumption')",
        )
        self.assert_rolled_back("usage.create", {"product_id": self.product_id, "tokens_used": 1})

    def test_restock_failure_after_quota_inventory_audit_and_task_writes(self) -> None:
        task = self.api(
            "staff", "restocks.create", {"account_id": self.account_id, "planned_amount": "300"}
        )
        self.inject(
            "RestockTask", "UPDATE", "EXISTS(SELECT 1 FROM inserted WHERE status='completed')"
        )
        self.assert_rolled_back(
            "restocks.complete", {"task_id": task["task_id"], "actual_amount": "300"}, "staff"
        )

    def test_refund_failure_after_lot_balance_ledger_and_order_writes(self) -> None:
        order = self.draft()
        self.api("customer", "orders.pay", order)
        self.inject(
            "Orders",
            "UPDATE",
            "EXISTS(SELECT 1 FROM inserted WHERE status IN('refunded','partially_refunded'))",
        )
        self.assert_rolled_back("refunds.request", order)


@unittest.skipUnless(
    bool(DATABASE),
    "Set DB_LAB_APP_DATABASE to an isolated Web database",
)
class AppSqlRaceTests(unittest.TestCase):
    def test_refund_serializes_concurrent_usage_then_both_units_rollback(self) -> None:
        monitor = connect()
        self.addCleanup(monitor.close)
        self.addCleanup(monitor.rollback)
        before = snapshot(monitor)
        cursor = monitor.cursor()
        candidate = cursor.execute("""
SELECT TOP(1) o.order_id,o.user_id,d.product_id
FROM dbo.Orders o JOIN dbo.Users u ON u.user_id=o.user_id
JOIN dbo.OrderDetails d ON d.order_id=o.order_id
JOIN dbo.OrderTokenLots l ON l.detail_id=d.detail_id
JOIN dbo.Products p ON p.product_id=d.product_id
JOIN dbo.TokenBalances b ON b.user_id=o.user_id AND b.model_provider=p.model_provider
WHERE o.status='paid' AND u.status='active' AND p.status='active'
AND l.issued_tokens-l.consumed_tokens-l.refunded_tokens>1 AND b.remaining_tokens>1
AND NOT EXISTS(SELECT 1 FROM dbo.RefundLedger r WHERE r.order_id=o.order_id)
AND EXISTS(SELECT 1 FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id
 WHERE a.provider=p.model_provider AND a.status='active' AND a.created_at<=SYSDATETIME()
 AND (a.expires_at IS NULL OR a.expires_at>SYSDATETIME())
 AND i.current_quota>=p.required_upstream_tokens AND i.current_quota=a.total_quota-a.used_quota)
ORDER BY o.order_id
""").fetchone()
        cursor.close()
        monitor.rollback()
        self.assertIsNotNone(
            candidate,
            "A paid historical order with unconsumed lots/current provider inventory is required",
        )
        order_id, user_id, product_id = map(int, candidate)
        refund_held = threading.Event()
        release_refund = threading.Event()
        usage_spids: queue.Queue[int] = queue.Queue()

        def worker(operation: str, payload: dict[str, object]) -> dict[str, object]:
            connection = connect()
            token = uuid.uuid4().bytes + uuid.uuid4().bytes
            try:
                cursor = connection.cursor()
                cursor.execute("EXEC app.StartSession 'customer',?,?", user_id, token).fetchall()
                if operation == "usage.create":
                    usage_spids.put(int(cursor.execute("SELECT @@SPID").fetchone()[0]))
                cursor.close()
                result = execute(connection, token, operation, payload)
                if operation == "refunds.request":
                    refund_held.set()
                    if not release_refund.wait(10):
                        raise AssertionError("Usage worker did not complete lock observation")
                return result
            finally:
                connection.rollback()
                connection.close()

        with ThreadPoolExecutor(max_workers=2) as pool:
            refund = pool.submit(worker, "refunds.request", {"order_id": order_id})
            try:
                self.assertTrue(
                    refund_held.wait(10), "Refund did not acquire its transaction locks"
                )
                usage = pool.submit(
                    worker, "usage.create", {"product_id": product_id, "tokens_used": 1}
                )
                usage_spid = usage_spids.get(timeout=5)
                observed_lock = False
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    cursor = monitor.cursor()
                    wait = cursor.execute(
                        "SELECT wait_type FROM sys.dm_exec_requests WHERE session_id=?", usage_spid
                    ).fetchone()
                    cursor.close()
                    monitor.rollback()
                    if wait and str(wait[0]).startswith("LCK_M_"):
                        observed_lock = True
                        break
                    if usage.done():
                        break
                    time.sleep(0.05)
                self.assertTrue(
                    observed_lock, "Concurrent usage failed to wait for the held refund transaction"
                )
                self.assertFalse(usage.done(), "Usage bypassed the uncommitted refund")
            finally:
                release_refund.set()
            self.assertEqual(refund.result(timeout=15)["order_id"], order_id)
            self.assertIn("log_id", usage.result(timeout=15))
        self.assertEqual(snapshot(monitor), before)
        cursor = monitor.cursor()
        self.assertEqual(
            cursor.execute(
                "SELECT COUNT(*) FROM dbo.TokenBalances WHERE remaining_tokens<0"
            ).fetchone()[0],
            0,
        )
        self.assertEqual(
            cursor.execute(
                "SELECT COUNT(*) FROM dbo.OrderTokenLots WHERE consumed_tokens+refunded_tokens>issued_tokens"
            ).fetchone()[0],
            0,
        )
        cursor.close()
