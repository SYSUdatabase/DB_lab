"""Live Flask → service → restricted SQL → accounting integration tests."""

from __future__ import annotations

import os
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

from webapp import create_app

DATABASE = os.environ.get("DB_LAB_APP_DATABASE", "")
PASSWORD = os.environ.get("DB_LAB_DEMO_PASSWORD", "")


@unittest.skipUnless(
    DATABASE.startswith("TokenHubDB_v11_Web") and PASSWORD,
    "Set isolated DB_LAB_APP_DATABASE and DB_LAB_DEMO_PASSWORD",
)
class WebIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = create_app(
            {
                "TESTING": True,
                "SECRET_KEY": "integration-only-key",
                "DB_DATABASE": DATABASE,
                "DB_PREVIEW": True,
            }
        )

    def login(self, account: str = "web_customer"):
        client = self.app.test_client()
        csrf = client.get("/api/v1/auth/session").json["data"]["csrf"]
        response = client.post(
            "/api/v1/auth/login",
            json={
                "kind": "employee" if account in {"web_staff", "web_admin"} else "customer",
                "account": account,
                "password": PASSWORD,
            },
            headers={"X-CSRF-Token": csrf},
        )
        self.assertEqual(response.status_code, 200, response.json)
        return client, {"X-CSRF-Token": response.json["data"]["csrf"]}

    def create_order(self, client, headers, quantity: int = 1) -> int:
        response = client.post(
            "/api/v1/orders",
            json={"items": [{"product_id": 1, "quantity": quantity}]},
            headers=headers,
        )
        self.assertEqual(response.status_code, 200, response.json)
        return response.json["data"]["order_id"]

    def test_01_purchase_usage_partial_refund_and_idempotence(self) -> None:
        client, headers = self.login()
        order = self.create_order(client, headers)
        paid = client.post(f"/api/v1/orders/{order}/pay", json={}, headers=headers)
        self.assertEqual(paid.status_code, 200, paid.json)
        usage = client.post(
            "/api/v1/usage", json={"product_id": 1, "tokens_used": "1000"}, headers=headers
        )
        self.assertEqual(usage.status_code, 200, usage.json)
        first = client.post(f"/api/v1/orders/{order}/refund", json={}, headers=headers)
        self.assertEqual(first.status_code, 200, first.json)
        second = client.post(f"/api/v1/orders/{order}/refund", json={}, headers=headers)
        self.assertEqual(second.status_code, 200, second.json)
        self.assertEqual(first.json["data"], second.json["data"])
        admin, admin_headers = self.login("web_admin")
        settled = admin.post(
            f"/api/v1/orders/{order}/settle",
            json={"external_payout_ref": f"SIM-API-{order}"},
            headers=admin_headers,
        )
        self.assertEqual(settled.status_code, 200, settled.json)

    def test_02_detail_update_delete_and_empty_payment(self) -> None:
        client, headers = self.login()
        order = self.create_order(client, headers)
        detail = client.get(f"/api/v1/orders/{order}").json["data"]["items"][0]["detail_id"]
        url = f"/api/v1/orders/{order}/items/{detail}"
        updated = client.put(url, json={"quantity": 3}, headers=headers)
        self.assertEqual(updated.status_code, 200, updated.json)
        result = client.get(f"/api/v1/orders/{order}").json["data"]
        self.assertEqual(result["items"][0]["quantity"], 3)
        self.assertEqual(client.delete(url, json={}, headers=headers).status_code, 200)
        self.assertEqual(
            client.post(f"/api/v1/orders/{order}/pay", json={}, headers=headers).status_code, 409
        )

    def test_03_cross_customer_and_role_bypass(self) -> None:
        owner, headers = self.login()
        order = self.create_order(owner, headers)
        other, other_headers = self.login("web_other")
        self.assertIn(other.get(f"/api/v1/orders/{order}").status_code, {403, 404})
        self.assertIn(
            other.post(f"/api/v1/orders/{order}/pay", json={}, headers=other_headers).status_code,
            {403, 404},
        )
        staff, staff_headers = self.login("web_staff")
        self.assertEqual(
            staff.post("/api/v1/products", json={}, headers=staff_headers).status_code, 403
        )
        self.assertEqual(
            owner.post(
                "/api/v1/orders", json={"user_id": 1, "items": []}, headers=headers
            ).status_code,
            400,
        )

    def test_04_bad_input_and_injection_are_not_sql(self) -> None:
        client, headers = self.login()
        response = client.get("/api/v1/products", query_string={"q": "'; DROP TABLE Users;--"})
        self.assertEqual(response.status_code, 200)
        for value in (-1, 0, 2147483648, True, "not-number"):
            response = client.post(
                "/api/v1/usage", json={"product_id": 1, "tokens_used": value}, headers=headers
            )
            self.assertEqual(response.status_code, 400, response.json)

    def test_05_logout_revokes_database_session(self) -> None:
        client, headers = self.login()
        with client.session_transaction() as cookie:
            old_cookie = dict(cookie)
        self.assertEqual(
            client.post("/api/v1/auth/logout", json={}, headers=headers).status_code, 200
        )
        with client.session_transaction() as cookie:
            cookie.update(old_cookie)
        self.assertEqual(client.get("/api/v1/orders").status_code, 401)

    def test_06_atomic_create_rejects_second_invalid_item(self) -> None:
        client, headers = self.login()
        before = client.get("/api/v1/orders").json["data"]["total"]
        response = client.post(
            "/api/v1/orders",
            json={
                "items": [
                    {"product_id": 1, "quantity": 1},
                    {"product_id": 2147483647, "quantity": 1},
                ]
            },
            headers=headers,
        )
        self.assertEqual(response.status_code, 409, response.json)
        self.assertEqual(client.get("/api/v1/orders").json["data"]["total"], before)

    def test_07_concurrent_payment_only_credits_once(self) -> None:
        client, headers = self.login()
        order = self.create_order(client, headers)

        def pay(_: int) -> int:
            worker, worker_headers = self.login()
            return worker.post(
                f"/api/v1/orders/{order}/pay", json={}, headers=worker_headers
            ).status_code

        with ThreadPoolExecutor(max_workers=2) as pool:
            codes = list(pool.map(pay, range(2)))
        self.assertEqual(sorted(codes), [200, 409])

    def test_08_token_values_are_wire_strings(self) -> None:
        client, _ = self.login()
        data = client.get("/api/v1/products").json["data"]["items"][0]
        self.assertIsInstance(data["token_amount"], str)
        self.assertIsInstance(data["price"], str)

    def test_09_connection_failure_is_safe(self) -> None:
        client, _ = self.login()
        with patch("webapp.dao.connect", side_effect=OSError("secret-host-SQL")):
            response = client.get("/api/v1/orders")
        self.assertEqual(response.status_code, 503)
        self.assertNotIn("secret-host-SQL", response.get_data(as_text=True))

    def test_10_concurrent_consumption_cannot_overdraw(self) -> None:
        client, headers = self.login("web_other")
        order = self.create_order(client, headers)
        self.assertEqual(
            client.post(f"/api/v1/orders/{order}/pay", json={}, headers=headers).status_code, 200
        )
        balances = client.get("/api/v1/balances").json["data"]["items"]
        amount = next(
            row["remaining_tokens"] for row in balances if row["model_provider"] == "OpenAI"
        )

        def consume(_: int) -> int:
            worker, worker_headers = self.login("web_other")
            return worker.post(
                "/api/v1/usage",
                json={"product_id": 1, "tokens_used": amount},
                headers=worker_headers,
            ).status_code

        with ThreadPoolExecutor(max_workers=2) as pool:
            codes = list(pool.map(consume, range(2)))
        self.assertEqual(sorted(codes), [200, 409])
        balances = client.get("/api/v1/balances").json["data"]["items"]
        self.assertTrue(all(int(row["remaining_tokens"]) >= 0 for row in balances))

    def test_11_refund_and_consumption_compete_for_same_tokens(self) -> None:
        client, headers = self.login("web_other")
        order = self.create_order(client, headers)
        self.assertEqual(
            client.post(f"/api/v1/orders/{order}/pay", json={}, headers=headers).status_code, 200
        )
        amount = client.get(f"/api/v1/orders/{order}").json["data"]["order"]["total_tokens"]

        def action(refund: bool) -> int:
            worker, worker_headers = self.login("web_other")
            path = f"/api/v1/orders/{order}/refund" if refund else "/api/v1/usage"
            payload = {} if refund else {"product_id": 1, "tokens_used": amount}
            return worker.post(path, json=payload, headers=worker_headers).status_code

        with ThreadPoolExecutor(max_workers=2) as pool:
            codes = list(pool.map(action, (False, True)))
        self.assertEqual(sorted(codes), [200, 409])
        balances = client.get("/api/v1/balances").json["data"]["items"]
        self.assertTrue(all(int(row["remaining_tokens"]) >= 0 for row in balances))


if __name__ == "__main__":
    unittest.main()
