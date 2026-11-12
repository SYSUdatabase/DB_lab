"""Stage-2 dashboard contract, access control and HTTP boundary tests."""

from pathlib import Path
from unittest import TestCase
from unittest.mock import patch

from webapp import create_app

ROOT = Path(__file__).resolve().parents[1]


class DashboardTests(TestCase):
    def setUp(self) -> None:
        app = create_app({"TESTING": True, "SECRET_KEY": "dashboard-test-only"})
        self.client = app.test_client()
        self.client.get("/")
        with self.client.session_transaction() as session:
            session["token"] = "synthetic-token-for-unit-test"

    def test_guest_cannot_view_global_counts(self) -> None:
        with (
            patch("webapp.services.identity", return_value={"role": "guest"}),
            patch("webapp.dao.dashboard") as query,
        ):
            response = self.client.get("/api/v1/dashboard")
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json["code"], "UNAUTHENTICATED")
        query.assert_not_called()

    def test_customer_cannot_view_global_counts(self) -> None:
        with (
            patch("webapp.services.identity", return_value={"role": "customer", "user_id": 1}),
            patch("webapp.dao.dashboard") as query,
        ):
            response = self.client.get("/api/v1/dashboard")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json["code"], "FORBIDDEN")
        query.assert_not_called()

    def test_employee_receives_aggregated_dashboard(self) -> None:
        fixture = {
            "metrics": {"total_orders": 5, "pending_orders": 2},
            "statuses": [{"status": "pending", "order_count": 2}],
            "daily_orders": [],
            "low_stock": [],
            "refreshed_at": "2026-11-12 12:00:00",
        }
        for role in ("staff", "admin"):
            with self.subTest(role=role):
                with (
                    patch("webapp.services.identity", return_value={"role": role}),
                    patch("webapp.dao.dashboard", return_value=fixture) as query,
                ):
                    response = self.client.get("/api/v1/dashboard")
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.json["data"]["metrics"]["total_orders"], 5)
                query.assert_called_once()

    def test_dashboard_rejects_unsupported_query_params(self) -> None:
        with (
            patch("webapp.services.identity", return_value={"role": "admin"}),
            patch("webapp.dao.dashboard") as query,
        ):
            response = self.client.get("/api/v1/dashboard?user_id=1")
        self.assertEqual(response.status_code, 400)
        query.assert_not_called()

    def test_sql_dashboard_contract_and_frontend(self) -> None:
        sql = (ROOT / "sql/app/dashboard.sql").read_text(encoding="utf-8")
        html = (ROOT / "webapp/templates/index.html").read_text(encoding="utf-8")
        js = (ROOT / "webapp/static/dashboard.js").read_text(encoding="utf-8")
        self.assertIn("WITH EXECUTE AS OWNER", sql)
        self.assertIn("s.revoked_at IS NULL", sql)
        self.assertIn("GRANT EXECUTE ON app.Dashboard TO app_runtime", sql)
        self.assertNotIn("GRANT SELECT", sql)
        self.assertIn("dashboard-panel", html)
        self.assertIn('api("/dashboard")', js)
        self.assertIn("15000", js)
