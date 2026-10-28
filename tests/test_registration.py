"""Customer sign-up validation and isolated HTTP/SQL integration."""

from __future__ import annotations

import os
import unittest
import uuid
from unittest.mock import patch

from webapp import create_app, services
from webapp.errors import AppError

DATABASE = os.environ.get("DB_LAB_APP_DATABASE", "")


class RegistrationValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.payload = {
            "account": "new_customer_123",
            "email": "new_customer_123@example.invalid",
            "password": "safe-test-password-123",
            "password_confirm": "safe-test-password-123",
        }

    def rejection(self, **updates: object) -> None:
        payload = {**self.payload, **updates}
        with patch("webapp.dao.authentication") as authentication:
            with self.assertRaises(AppError) as raised:
                services.register(payload)
        self.assertEqual(raised.exception.code, "INVALID_INPUT")
        authentication.assert_not_called()

    def test_invalid_account_and_email(self) -> None:
        for account in ("", "ab", "illegal name", "汉字名", "a" * 51):
            with self.subTest(account=account):
                self.rejection(account=account)
        for email in ("", "bad@", "xx@bad", "bad@example.invalid ", "汉字@example.com"):
            with self.subTest(email=email):
                self.rejection(email=email)

    def test_reject_weak_unmatched_or_nonstring_password(self) -> None:
        self.rejection(password="short", password_confirm="short")
        self.rejection(password_confirm="other-password")
        self.rejection(password=["not", "a", "password"])
        self.rejection(password="x" * 73, password_confirm="x" * 73)

    def test_reject_role_escalation_and_unexpected_fields(self) -> None:
        for extra in ({"role": "admin"}, {"employee_id": 1}, {"status": "active"}):
            with self.subTest(extra=extra):
                payload = {**self.payload, **extra}
                with patch("webapp.dao.authentication") as authentication:
                    with self.assertRaises(AppError):
                        services.register(payload)
                    authentication.assert_not_called()

    def test_csrf_is_required_before_db_access(self) -> None:
        app = create_app({"TESTING": True, "SECRET_KEY": "registration-tests"})
        client = app.test_client()
        with patch("webapp.dao.authentication") as authentication:
            response = client.post("/api/v1/auth/register", json=self.payload)
        self.assertEqual(response.status_code, 403)
        authentication.assert_not_called()


@unittest.skipUnless(
    DATABASE.startswith("TokenHubDB_v11_Web"),
    "Registration integration requires explicitly selected isolated Web v1.1 DB",
)
class RegistrationIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = create_app(
            {
                "TESTING": True,
                "SECRET_KEY": "registration-integration-only",
                "DB_DATABASE": DATABASE,
                "DB_PREVIEW": True,
            }
        )

    def client(self):
        client = self.app.test_client()
        csrf = client.get("/api/v1/auth/session").json["data"]["csrf"]
        return client, {"X-CSRF-Token": csrf}

    def test_register_and_login_duplicates_and_forbidden_admin(self) -> None:
        token = uuid.uuid4().hex[:14]
        username = "signup_" + token
        email = username + "@example.invalid"
        password = "demo-registration-Pass123!"
        client, headers = self.client()
        payload = {
            "account": username,
            "email": email,
            "password": password,
            "password_confirm": password,
        }
        response = client.post("/api/v1/auth/register", json=payload, headers=headers)
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(response.json["data"]["role"], "customer")
        fresh_csrf = response.json["data"]["csrf"]
        self.assertEqual(client.get("/api/v1/auth/session").json["data"]["role"], "customer")
        # Public customer can never administer products or register staff.
        forbidden = client.post("/api/v1/products", json={}, headers={"X-CSRF-Token": fresh_csrf})
        self.assertEqual(forbidden.status_code, 403)
        self.assertEqual(
            client.post(
                "/api/v1/auth/register",
                json=payload,
                headers={"X-CSRF-Token": fresh_csrf},
            ).status_code,
            409,
        )
        client.post("/api/v1/auth/logout", json={}, headers={"X-CSRF-Token": fresh_csrf})
        login_csrf = client.get("/api/v1/auth/session").json["data"]["csrf"]
        login = client.post(
            "/api/v1/auth/login",
            json={"kind": "customer", "account": username, "password": password},
            headers={"X-CSRF-Token": login_csrf},
        )
        self.assertEqual(login.status_code, 200, login.json)
        self.assertEqual(login.json["data"]["role"], "customer")
        second, headers2 = self.client()
        duplicate = second.post("/api/v1/auth/register", json=payload, headers=headers2)
        self.assertEqual(duplicate.status_code, 409, duplicate.json)
        self.assertEqual(duplicate.json["code"], "CONSTRAINT_CONFLICT")
        other = {
            **payload,
            "account": "another_" + token,
            "email": email,
        }
        duplicate_email = second.post("/api/v1/auth/register", json=other, headers=headers2)
        self.assertEqual(duplicate_email.status_code, 409, duplicate_email.json)

    def test_bad_request_does_not_create_any_user(self) -> None:
        client, headers = self.client()
        payload = {
            "account": "new_" + uuid.uuid4().hex[:12],
            "email": "valid@example.invalid",
            "password": "sufficiently-long-pw",
            "password_confirm": "different-password",
        }
        response = client.post("/api/v1/auth/register", json=payload, headers=headers)
        self.assertEqual(response.status_code, 400, response.json)
        self.assertEqual(response.json["code"], "INVALID_INPUT")


if __name__ == "__main__":
    unittest.main()
