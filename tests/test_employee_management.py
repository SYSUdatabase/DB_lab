"""Admin-only staff lifecycle, session revocation, and no destructive employee deletion."""

from __future__ import annotations

import os
import unittest
import uuid
from unittest.mock import patch

import pyodbc

from webapp import create_app, services
from webapp.errors import AppError

DATABASE = os.environ.get("DB_LAB_APP_DATABASE", "")
DEMO_PASSWORD = os.environ.get("DB_LAB_DEMO_PASSWORD", "")


class EmployeeValidationTests(unittest.TestCase):
    def test_role_and_extra_fields_not_accepted(self) -> None:
        valid = {
            "name": "Example Staff",
            "account": "staff_test",
            "password": "safe-password-12345",
            "password_confirm": "safe-password-12345",
        }
        for extra in ({"role": "admin"}, {"status": "active"}, {"employee_id": 1}):
            with self.subTest(extra=extra), self.assertRaises(AppError):
                services.employee_payload("employees.create", {**valid, **extra})

    def test_bad_password_and_account_rejected(self) -> None:
        valid = {
            "name": "Example Staff",
            "account": "staff_test",
            "password": "safe-password-12345",
            "password_confirm": "safe-password-12345",
        }
        for key, value in (
            ("account", "bad account"),
            ("account", "x"),
            ("name", ""),
            ("password", "short"),
            ("password_confirm", "different"),
        ):
            with self.subTest(key=key, value=value), self.assertRaises(AppError):
                services.employee_payload("employees.create", {**valid, key: value})

    def test_reject_self_requested_role_change_and_arbitrary_id(self) -> None:
        for op, payload in (
            ("employees.update", {"employee_id": 2, "name": "x", "role": "admin"}),
            ("employees.status", {"employee_id": 1, "status": "deleted"}),
            (
                "employees.password",
                {"employee_id": -1, "password": "abcd", "password_confirm": "abcd"},
            ),
        ):
            with self.subTest(op=op), self.assertRaises(AppError):
                services.employee_payload(op, payload)

    def test_missing_csrf_blocks_management_before_database(self) -> None:
        app = create_app({"TESTING": True, "SECRET_KEY": "staff-boundary"})
        client = app.test_client()
        with patch("webapp.dao.connect") as connect:
            response = client.post("/api/v1/employees", json={"role": "admin"})
        self.assertEqual(response.status_code, 403)
        connect.assert_not_called()


@unittest.skipUnless(
    DATABASE.startswith("TokenHubDB_v11_Web") and DEMO_PASSWORD,
    "Requires isolated DB_LAB_APP_DATABASE and DB_LAB_DEMO_PASSWORD",
)
class EmployeeIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = create_app(
            {
                "TESTING": True,
                "SECRET_KEY": "staff-integration",
                "DB_DATABASE": DATABASE,
                "DB_PREVIEW": True,
            }
        )

    def login(self, account: str, password: str = DEMO_PASSWORD, kind: str = "employee"):
        client = self.app.test_client()
        csrf = client.get("/api/v1/auth/session").json["data"]["csrf"]
        response = client.post(
            "/api/v1/auth/login",
            json={"kind": kind, "account": account, "password": password},
            headers={"X-CSRF-Token": csrf},
        )
        return client, response, {"X-CSRF-Token": (response.json.get("data") or {}).get("csrf", "")}

    def test_create_edit_password_disable_enable_and_history(self) -> None:
        admin, response, headers = self.login("web_admin")
        self.assertEqual(response.status_code, 200, response.json)
        token = uuid.uuid4().hex[:12]
        account = "newstaff_" + token
        password = "employee-Start-12345"
        new_password = "employee-Reset-54321"
        created = admin.post(
            "/api/v1/employees",
            json={
                "name": "Test Operator",
                "account": account,
                "password": password,
                "password_confirm": password,
            },
            headers=headers,
        )
        self.assertEqual(created.status_code, 200, created.json)
        identifier = int(created.json["data"]["employee_id"])
        rows = admin.get("/api/v1/employees?page=1&q=").json["data"]["items"]
        self.assertTrue(any(x["employee_id"] == identifier and x["role"] == "staff" for x in rows))
        self.assertFalse(any("password_hash" in x for x in rows))
        self.assertFalse(any(x["role"] == "admin" for x in rows))

        staff, logged, staff_headers = self.login(account, password)
        self.assertEqual(logged.status_code, 200, logged.json)
        self.assertEqual(logged.json["data"]["role"], "staff")
        self.assertEqual(staff.get("/api/v1/employees").status_code, 403)
        self.assertEqual(
            staff.post(
                "/api/v1/employees",
                json={"name": "Evil", "account": "evi", "role": "admin"},
                headers=staff_headers,
            ).status_code,
            403,
        )

        changed = admin.put(
            f"/api/v1/employees/{identifier}",
            json={"name": "Updated Operator"},
            headers=headers,
        )
        self.assertEqual(changed.status_code, 200, changed.json)

        disabled = admin.post(
            f"/api/v1/employees/{identifier}/status",
            json={"status": "inactive"},
            headers=headers,
        )
        self.assertEqual(disabled.status_code, 200, disabled.json)
        self.assertEqual(staff.get("/api/v1/orders").status_code, 401)
        self.assertEqual(self.login(account, password)[1].status_code, 401)

        enabled = admin.post(
            f"/api/v1/employees/{identifier}/status",
            json={"status": "active"},
            headers=headers,
        )
        self.assertEqual(enabled.status_code, 200, enabled.json)
        staff_again, fresh, _ = self.login(account, password)
        self.assertEqual(fresh.status_code, 200, fresh.json)

        reset = admin.post(
            f"/api/v1/employees/{identifier}/password",
            json={"password": new_password, "password_confirm": new_password},
            headers=headers,
        )
        self.assertEqual(reset.status_code, 200, reset.json)
        self.assertEqual(staff_again.get("/api/v1/orders").status_code, 401)
        self.assertEqual(self.login(account, password)[1].status_code, 401)
        self.assertEqual(self.login(account, new_password)[1].status_code, 200)

        # There is deliberately no employee DELETE API; lifecycle is status-based.
        self.assertEqual(
            admin.delete(f"/api/v1/employees/{identifier}", json={}, headers=headers).status_code,
            405,
        )
        # Admin employee IDs are never writable through the staff-only procedure.
        with pyodbc.connect(
            "DRIVER={ODBC Driver 18 for SQL Server};"
            r"SERVER=localhost\SQLEXPRESS;"
            f"DATABASE={DATABASE};Trusted_Connection=yes;TrustServerCertificate=yes;"
        ) as conn:
            cursor = conn.cursor()
            count = cursor.execute(
                "SELECT COUNT(*) FROM dbo.Employees WHERE employee_id=? AND status='active'",
                identifier,
            ).fetchval()
            self.assertEqual(count, 1)
            admin_id = int(
                cursor.execute(
                    "SELECT employee_id FROM dbo.Employees WHERE account='web_admin'"
                ).fetchval()
            )
            self.assertEqual(
                cursor.execute(
                    "SELECT status FROM dbo.Employees WHERE employee_id=?", admin_id
                ).fetchval(),
                "active",
            )
        self.assertEqual(
            admin.post(
                f"/api/v1/employees/{admin_id}/status",
                json={"status": "inactive"},
                headers=headers,
            ).status_code,
            404,
        )
        self.assertEqual(
            admin.post(
                "/api/v1/employees",
                json={
                    "name": "Escalation",
                    "account": "escalation_" + token,
                    "password": password,
                    "password_confirm": password,
                    "role": "admin",
                },
                headers=headers,
            ).status_code,
            400,
        )

    def test_duplicate_account_and_no_customer_or_staff_access(self) -> None:
        admin, response, headers = self.login("web_admin")
        self.assertEqual(response.status_code, 200, response.json)
        duplicate = admin.post(
            "/api/v1/employees",
            json={
                "name": "Duplicate",
                "account": "web_staff",
                "password": "strongPassword-12345",
                "password_confirm": "strongPassword-12345",
            },
            headers=headers,
        )
        self.assertEqual(duplicate.status_code, 409, duplicate.json)
        customer, logged, customer_headers = self.login("web_customer", kind="customer")
        self.assertEqual(logged.status_code, 200)
        self.assertEqual(customer.get("/api/v1/employees?page=1&q=").status_code, 403)
        self.assertEqual(
            customer.post(
                "/api/v1/employees",
                json={"name": "Bad"},
                headers=customer_headers,
            ).status_code,
            403,
        )
        guest = self.app.test_client()
        self.assertEqual(guest.get("/api/v1/employees?page=1&q=").status_code, 401)


if __name__ == "__main__":
    unittest.main()
