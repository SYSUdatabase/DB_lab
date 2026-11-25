"""Regression: upstream restock recovery and precise Web conflict feedback."""

from __future__ import annotations

import os
import secrets
import unittest
from contextlib import closing

import pyodbc

from tools.week13_verify import connect, select
from webapp import create_app
from webapp.errors import database_error
from webapp.services import digest

DATABASE = os.environ.get("DB_LAB_WEEK13_DATABASE", "")
SERVER = os.environ.get("DB_LAB_TEST_SERVER", r"localhost\SQLEXPRESS")


class ConflictMessageTests(unittest.TestCase):
    def test_specific_conflicts_are_safe(self) -> None:
        cases = {
            53131: "ORDER_ALREADY_PAID",
            53132: "INSUFFICIENT_SELLABLE_QUOTA",
            53125: "ORDER_EMPTY",
            53311: "RESTOCK_ALREADY_COMPLETED",
            53312: "RESTOCK_CLOSED",
            55010: "INVENTORY_BUSY",
        }
        for number, code in cases.items():
            with self.subTest(number=number):
                error = database_error(Exception(f"private detail ({number})"))
                self.assertEqual((error.code, error.status), (code, 409))
                self.assertNotIn("private detail", error.message)


@unittest.skipUnless(DATABASE, "Set DB_LAB_WEEK13_DATABASE to a disposable WebW13 database")
class RestockFeedbackTests(unittest.TestCase):
    def setUp(self) -> None:
        self.assertRegex(DATABASE, r"^TokenHubDB_v11_WebW13[A-Za-z0-9]{2,9}$")
        self.db = connect(SERVER, DATABASE)
        self.addCleanup(self.db.close)
        self.employee = int(
            str(
                select(self.db, "SELECT employee_id FROM dbo.Employees WHERE account='web_admin';")[
                    0
                ]["employee_id"]
            )
        )
        self.app = create_app(
            {
                "TESTING": True,
                "SECRET_KEY": secrets.token_hex(32),
                "DB_SERVER": SERVER,
                "DB_DATABASE": DATABASE,
                "DB_PREVIEW": True,
            }
        )

    def fixture(self, status: str, expired: bool = False) -> tuple[int, int]:
        # Dedicated records, initially zero usable quota; no existing account is edited.
        tag = secrets.token_hex(6)
        with closing(self.db.cursor()) as cur:
            account = int(
                cur.execute(
                    "SET NOCOUNT ON; INSERT dbo.UpstreamAccount(provider,account_name,api_key,"
                    "total_quota,used_quota,safety_threshold,status,created_at,expires_at) "
                    "VALUES('OpenAI',?,'fixture-unusable',100,100,10,?,"
                    "DATEADD(day,-2,SYSDATETIME()),DATEADD(day,?,SYSDATETIME())); "
                    "SELECT CONVERT(INT,SCOPE_IDENTITY());",
                    "Restock status " + tag,
                    status,
                    -1 if expired else 30,
                ).fetchval()
            )
            task = int(
                cur.execute(
                    "SET NOCOUNT ON; INSERT dbo.RestockTask(account_id,trigger_reason,restock_method,"
                    "target_amount,created_by,assigned_to,status) "
                    "VALUES(?,'manual','manual_purchase',10000,?,?,'pending'); "
                    "SELECT CONVERT(INT,SCOPE_IDENTITY());",
                    account,
                    self.employee,
                    self.employee,
                ).fetchval()
            )
        return account, task

    def state(self, account: int, task: int) -> dict[str, object]:
        return select(
            self.db,
            """SELECT a.status account_status,a.total_quota,a.used_quota,
i.current_quota,t.status task_status,t.actual_amount,t.completed_at,
(SELECT COUNT(*) FROM dbo.InventoryLog WHERE account_id=a.account_id) log_count,
(SELECT COUNT(*) FROM w11.InventoryAudit WHERE account_id=a.account_id) audit_count
FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id
JOIN dbo.RestockTask t ON t.account_id=a.account_id WHERE a.account_id=? AND t.task_id=?;""",
            account,
            task,
        )[0]

    def available(self) -> int:
        return int(
            str(
                select(self.db, "SELECT available_quota FROM w11.fn_ProviderSellable('OpenAI');")[
                    0
                ]["available_quota"]
            )
        )

    def client_for(self, kind: str, identifier: int):
        client = self.app.test_client()
        token, csrf = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        with closing(self.db.cursor()) as cur:
            cur.execute("EXEC app.StartSession ?,?,?;", kind, identifier, digest(token)).fetchall()
        self.addCleanup(lambda: self.db.execute("EXEC app.EndSession ?;", digest(token)))
        with client.session_transaction() as session:
            session.update(token=token, csrf=csrf)
        return client, {"X-CSRF-Token": csrf}

    def test_restock_status_and_sellable_quota(self) -> None:
        for status, expired, expected, gain in (
            ("active", False, "active", 10000),
            ("depleted", False, "active", 10000),
            ("suspended", False, "suspended", 0),
            ("depleted", True, "depleted", 0),
        ):
            with self.subTest(status=status, expired=expired):
                account, task = self.fixture(status, expired)
                before = self.state(account, task)
                available = self.available()
                select(self.db, "EXEC w12.usp_ReceiveRestock ?,10000,0;", task)
                after = self.state(account, task)
                self.assertEqual(after["account_status"], expected)
                self.assertEqual(after["total_quota"], 10100)
                self.assertEqual(after["used_quota"], 100)
                self.assertEqual(after["current_quota"], 10000)
                self.assertEqual(after["task_status"], "completed")
                self.assertEqual(after["actual_amount"], 10000)
                self.assertIsNotNone(after["completed_at"])
                self.assertEqual(after["log_count"], int(str(before["log_count"])) + 1)
                self.assertEqual(after["audit_count"], int(str(before["audit_count"])) + 1)
                self.assertEqual(self.available() - available, gain)

    def test_restock_activation_rollback_and_duplicate(self) -> None:
        account, task = self.fixture("depleted")
        before = self.state(account, task)
        available = self.available()
        select(
            self.db,
            "EXEC sys.sp_set_session_context @key=N'w12.fail_point',@value=N'restock_after_inventory';",
        )
        try:
            with self.assertRaisesRegex(pyodbc.Error, r"\(54491\)"):
                select(self.db, "EXEC w12.usp_ReceiveRestock ?,10000,0;", task)
        finally:
            select(self.db, "EXEC sys.sp_set_session_context @key=N'w12.fail_point',@value=NULL;")
        self.assertEqual(self.state(account, task), before)
        self.assertEqual(self.available(), available)
        self.assertEqual(select(self.db, "SELECT @@TRANCOUNT AS n;"), [{"n": 0}])
        select(self.db, "EXEC w12.usp_ReceiveRestock ?,10000,0;", task)
        completed = self.state(account, task)
        self.assertEqual(completed["account_status"], "active")
        with self.assertRaisesRegex(pyodbc.Error, r"\(53311\)"):
            select(self.db, "EXEC w12.usp_ReceiveRestock ?,10000,0;", task)
        self.assertEqual(self.state(account, task), completed)

    def test_web_restock_and_order_feedback(self) -> None:
        client, headers = self.client_for("employee", self.employee)
        account, task = self.fixture("depleted")
        url = f"/api/v1/restocks/{task}/complete"
        response = client.post(url, json={"actual_amount": "10000"}, headers=headers)
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(self.state(account, task)["account_status"], "active")
        response = client.post(url, json={"actual_amount": "10000"}, headers=headers)
        self.assertEqual(
            (response.status_code, response.json["code"]), (409, "RESTOCK_ALREADY_COMPLETED")
        )
        _, closed = self.fixture("active")
        select(self.db, "UPDATE dbo.RestockTask SET status='failed' WHERE task_id=?;", closed)
        response = client.post(
            f"/api/v1/restocks/{closed}/complete", json={"actual_amount": "1"}, headers=headers
        )
        self.assertEqual((response.status_code, response.json["code"]), (409, "RESTOCK_CLOSED"))
        uid = int(
            str(
                select(self.db, "SELECT user_id FROM dbo.Users WHERE username='web_customer';")[0][
                    "user_id"
                ]
            )
        )
        customer, headers = self.client_for("customer", uid)
        created = customer.post(
            "/api/v1/orders", json={"items": [{"product_id": 1, "quantity": 1}]}, headers=headers
        )
        self.assertEqual(created.status_code, 200, created.json)
        order = created.json["data"]["order_id"]
        self.assertEqual(
            customer.post(f"/api/v1/orders/{order}/pay", json={}, headers=headers).status_code, 200
        )
        duplicate = customer.post(f"/api/v1/orders/{order}/pay", json={}, headers=headers)
        self.assertEqual(
            (duplicate.status_code, duplicate.json["code"]), (409, "ORDER_ALREADY_PAID")
        )
        created = customer.post(
            "/api/v1/orders", json={"items": [{"product_id": 1, "quantity": 1}]}, headers=headers
        )
        self.assertEqual(created.status_code, 200, created.json)
        order = created.json["data"]["order_id"]
        detail = customer.get(f"/api/v1/orders/{order}").json["data"]["items"][0]["detail_id"]
        self.assertEqual(
            customer.delete(
                f"/api/v1/orders/{order}/items/{detail}", json={}, headers=headers
            ).status_code,
            200,
        )
        empty = customer.post(f"/api/v1/orders/{order}/pay", json={}, headers=headers)
        self.assertEqual((empty.status_code, empty.json["code"]), (409, "ORDER_EMPTY"))
        # Ask for more than the entire active provider capacity, even before reservations.
        unit = int(
            str(
                select(
                    self.db, "SELECT required_upstream_tokens FROM dbo.Products WHERE product_id=1;"
                )[0]["required_upstream_tokens"]
            )
        )
        quantity = self.available() // unit + 1
        created = customer.post(
            "/api/v1/orders",
            json={"items": [{"product_id": 1, "quantity": quantity}]},
            headers=headers,
        )
        self.assertEqual(created.status_code, 200, created.json)
        order = created.json["data"]["order_id"]
        insufficient = customer.post(f"/api/v1/orders/{order}/pay", json={}, headers=headers)
        self.assertEqual(
            (insufficient.status_code, insufficient.json["code"]),
            (409, "INSUFFICIENT_SELLABLE_QUOTA"),
        )
        self.assertEqual(
            select(self.db, "SELECT status FROM dbo.Orders WHERE order_id=?;", order),
            [{"status": "pending"}],
        )
        self.assertEqual(
            customer.post(f"/api/v1/orders/{order}/cancel", json={}, headers=headers).status_code,
            200,
        )
        cancelled = customer.post(f"/api/v1/orders/{order}/pay", json={}, headers=headers)
        self.assertEqual(
            (cancelled.status_code, cancelled.json["code"]), (409, "ORDER_NOT_PENDING")
        )

    def test_expired_status_cannot_be_restocked(self) -> None:
        account, task = self.fixture("expired", True)
        before = self.state(account, task)
        available = self.available()
        with self.assertRaisesRegex(pyodbc.Error, r"\(53305\)"):
            select(self.db, "EXEC w12.usp_ReceiveRestock ?,10000,0;", task)
        self.assertEqual(self.state(account, task), before)
        self.assertEqual(self.available(), available)
        self.assertEqual(select(self.db, "SELECT @@TRANCOUNT AS n;"), [{"n": 0}])
