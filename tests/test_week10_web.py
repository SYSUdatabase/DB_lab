"""Week 10 HTTP policy, validation and precision contracts."""

import unittest
from unittest.mock import MagicMock, patch

from flask import Response

from webapp import create_app, dao
from webapp.errors import database_error


class Week10WebTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = create_app({"TESTING": True, "SECRET_KEY": "week10-test"}).test_client()
        with self.client.session_transaction() as session:
            session.update(token="test-token", csrf="test-csrf")

    def request(
        self, path: str, role: str = "admin", payload: dict[str, object] | None = None
    ) -> tuple[Response, MagicMock]:
        with (
            patch("webapp.services.identity", return_value={"role": role}),
            patch("webapp.dao.week10", return_value={"items": [], "total": 0}) as execute,
        ):
            if payload is None:
                response = self.client.get("/api/v1" + path)
            else:
                response = self.client.post(
                    "/api/v1" + path, json=payload, headers={"X-CSRF-Token": "test-csrf"}
                )
        return response, execute

    def test_sales_validates_dates_and_roles(self) -> None:
        for dates in (
            "start_date=2026-02-30&end_date=2026-03-01",
            "start_date=2026-02-02&end_date=2026-01-01",
        ):
            response, execute = self.request("/reports/sales?" + dates)
            self.assertEqual(response.status_code, 400)
            execute.assert_not_called()
        response, execute = self.request(
            "/reports/sales?start_date=2026-01-01&end_date=2026-11-11", "staff"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(execute.call_args.args[1], "reports.sales")
        response, execute = self.request(
            "/reports/sales?start_date=2026-01-01&end_date=2026-11-11", "customer"
        )
        self.assertEqual(response.status_code, 403)
        execute.assert_not_called()

    def test_recommendation_bigint_and_optional_minimum(self) -> None:
        response, execute = self.request(
            "/restocks/recommendation?product_id=1&account_id=2&target_quota=9223372036854775807",
            "staff",
        )
        self.assertEqual(response.status_code, 200)
        self.assertIsNone(execute.call_args.args[2]["minimum_quota"])
        response, execute = self.request(
            "/restocks/recommendation?product_id=1&account_id=2&target_quota=9&minimum_quota=10"
        )
        self.assertEqual(response.status_code, 400)
        execute.assert_not_called()

    def test_adjustment_signed_range_and_forgery(self) -> None:
        payload = {
            "product_id": 1,
            "account_id": 2,
            "change_amount": "-9223372036854775808",
            "reason": "校正" * 100,
            "operation_key": "398d1774-f684-4526-9222-a2a86976283b",
        }
        response, execute = self.request("/inventory/adjustments", payload=payload)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(execute.call_args.args[2]["change_amount"], payload["change_amount"])
        for changes in (
            {"employee_id": 4},
            {"discount_rate": "0.9"},
            {"change_amount": "0"},
            {"change_amount": "-9223372036854775809"},
            {"operation_key": "bad"},
        ):
            response, execute = self.request(
                "/inventory/adjustments", payload={**payload, **changes}
            )
            self.assertEqual(response.status_code, 400)
            execute.assert_not_called()
        response, execute = self.request("/inventory/adjustments", role="staff", payload=payload)
        self.assertEqual(response.status_code, 403)
        execute.assert_not_called()

    def test_list_defaults_and_csrf(self) -> None:
        response, execute = self.request("/inventory/adjustments")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(execute.call_args.args[2], {"page": 1})
        self.assertEqual(
            self.client.post("/api/v1/inventory/adjustments", json={}).status_code, 403
        )

    def test_wire_precision_and_errors(self) -> None:
        values = {
            key: 9223372036854775807
            for key in (
                "order_count",
                "adjustment_id",
                "sales_quantity",
                "recommended_quantity",
                "change_amount",
                "sales_amount",
                "original_subtotal",
                "discount_rate",
                "discount_amount",
            )
        }
        self.assertTrue(all(isinstance(value, str) for value in dao.wire_values(values).values()))
        for number, status in (
            (56000, 400),
            (56001, 401),
            (56003, 403),
            (56004, 404),
            (56009, 409),
        ):
            self.assertEqual(database_error(Exception(f"failure ({number})")).status, status)

    def test_dao_binds_week10_parameters_and_preserves_bigint(self) -> None:
        connection = MagicMock()
        cursor = connection.cursor.return_value.execute.return_value
        cursor.description = [("data",)]
        cursor.fetchall.return_value = [('{"recommended_quantity":9223372036854775807}',)]
        app = create_app({"TESTING": True, "SECRET_KEY": "week10-test"})
        with app.app_context(), patch("webapp.dao.connect", return_value=connection):
            result = dao.week10(b"session-hash", "restocks.recommendation", {"account_id": 2})
        self.assertEqual(result, {"recommended_quantity": "9223372036854775807"})
        connection.cursor.return_value.execute.assert_called_once_with(
            "EXEC app.Week10 @token_hash=?, @operation=?, @payload=?",
            b"session-hash",
            "restocks.recommendation",
            '{"account_id": 2}',
        )
        connection.commit.assert_called_once()
        connection.close.assert_called_once()

    def test_order_rejects_client_pricing(self) -> None:
        for field in (
            "unit_price",
            "price",
            "discount_rate",
            "discount_amount",
            "pricing_rule_version",
            "original_subtotal",
            "subtotal",
            "total_amount",
        ):
            with (
                patch("webapp.services.identity", return_value={"role": "customer"}),
                patch("webapp.dao.execute") as execute,
            ):
                response = self.client.post(
                    "/api/v1/orders",
                    json={"items": [{"product_id": 1, "quantity": 1}], field: "1"},
                    headers={"X-CSRF-Token": "test-csrf"},
                )
            self.assertEqual(response.status_code, 400)
            execute.assert_not_called()

    def test_list_optional_filters(self) -> None:
        response, execute = self.request(
            "/inventory/adjustments?account_id=18&product_id=2&page_size=50"
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            execute.call_args.args[2],
            {"page": 1, "account_id": 18, "product_id": 2, "page_size": 50},
        )
        for query in (
            "account_id=0",
            "product_id=2147483648",
            "page_size=101",
            "page_size=true",
            "account_id=1.5",
        ):
            response, execute = self.request("/inventory/adjustments?" + query)
            self.assertEqual(response.status_code, 400)
            execute.assert_not_called()

    def test_reason_uses_utf16_storage_limit(self) -> None:
        payload = {
            "product_id": 1,
            "account_id": 2,
            "change_amount": "1",
            "reason": "😀" * 128,
            "operation_key": "398d1774-f684-4526-9222-a2a86976283b",
        }
        response, execute = self.request("/inventory/adjustments", payload=payload)
        self.assertEqual(response.status_code, 400)
        execute.assert_not_called()
        response, execute = self.request(
            "/inventory/adjustments", payload={**payload, "reason": "😀" * 127 + "字"}
        )
        self.assertEqual(response.status_code, 200)

    def test_numeric_sql_overflow_is_input_error(self) -> None:
        self.assertEqual(database_error(Exception("Arithmetic overflow (8115)")).status, 400)
