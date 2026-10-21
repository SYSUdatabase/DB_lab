"""HTTP boundary tests: rejection must happen before database access."""

import unittest
from unittest.mock import MagicMock, patch

import pyodbc

from webapp import create_app


class HttpBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app({"TESTING": True, "SECRET_KEY": "test-only-key"})
        self.client = self.app.test_client()

    def test_shell_and_security_headers(self):
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertIn("Content-Security-Policy", response.headers)

    def test_mutation_requires_csrf_before_database(self):
        with patch("webapp.dao.connect") as connect:
            response = self.client.post("/api/v1/orders", json={"items": []})
        self.assertEqual(response.status_code, 403)
        connect.assert_not_called()

    def test_database_unavailable_is_sanitized(self):
        with patch("webapp.dao.connect", side_effect=OSError("private-server-path")):
            response = self.client.get("/api/v1/products")
        self.assertEqual(response.status_code, 503)
        self.assertNotIn(b"private-server-path", response.data)
        self.assertEqual(set(response.json), {"code", "message", "data", "request_id"})

    def test_unknown_api_is_json(self):
        self.assertEqual(self.client.get("/api/v1/absent").json["code"], "NOT_FOUND")

    def test_invalid_operation_not_exposed(self):
        self.assertEqual(self.client.post("/api/v1/execute").status_code, 404)

    def test_login_rejects_structured_kind(self):
        csrf = self.client.get("/api/v1/auth/session").json["data"]["csrf"]
        with patch("webapp.dao.connect") as connect:
            response = self.client.post(
                "/api/v1/auth/login",
                json={"kind": [], "account": "test", "password": "test"},
                headers={"X-CSRF-Token": csrf},
            )
        self.assertEqual(response.status_code, 400)
        connect.assert_not_called()

    def test_disconnect_cleanup_does_not_mask_service_unavailable(self):
        connection = MagicMock()
        connection.cursor.return_value.execute.side_effect = pyodbc.Error(
            "08S01", "communication link failure"
        )
        connection.rollback.side_effect = pyodbc.Error("08003", "connection no longer open")
        with patch("webapp.dao.connect", return_value=connection):
            response = self.client.get("/api/v1/products")
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json["code"], "DATABASE_UNAVAILABLE")
        connection.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
