"""Week 10 database contracts against an explicitly selected disposable Web database."""

from __future__ import annotations

import json
import os
import re
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parents[1]
DATABASE = os.environ.get("DB_LAB_WEEK10_DATABASE", "")
SERVER = os.environ.get("DB_LAB_TEST_SERVER", r"localhost\SQLEXPRESS")


def connect() -> pyodbc.Connection:
    """Require deliberate selection, including when imported by the evidence runner."""
    if not re.fullmatch(r"TokenHubDB_v11_Web[A-Za-z0-9_]+", DATABASE):
        raise ValueError("DB_LAB_WEEK10_DATABASE must name an isolated v11 Web database")
    if "base" in DATABASE.lower():
        raise ValueError("The pre-extension baseline database is read-only")
    return pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};"
        "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;",
        autocommit=False,
        timeout=15,
    )


class Week10SourceTests(unittest.TestCase):
    def test_explicit_extension_and_narrow_grant(self) -> None:
        source = (ROOT / "sql/app/week10.sql").read_text(encoding="utf-8")
        self.assertIn("GRANT EXECUTE ON app.Week10 TO app_runtime", source)
        self.assertNotRegex(source, r"(?i)GRANT\s+(SELECT|INSERT|UPDATE|DELETE|CONTROL)")
        self.assertNotRegex(source, r"(?i)GRANT EXECUTE ON SCHEMA")
        self.assertIn("WITH EXECUTE AS OWNER", source)


@unittest.skipUnless(
    DATABASE, "Set DB_LAB_WEEK10_DATABASE to an isolated installed Week 10 database"
)
class Week10SqlTests(unittest.TestCase):
    """Transactions roll back, except tagged fixtures for the two-connection tests."""

    def assertEqual(self, first: object, second: object, msg: str | None = None) -> None:
        if hasattr(self, "events"):
            self.events.append({"assertion": "equal", "actual": first, "expected": second})
        super().assertEqual(first, second, msg)

    def setUp(self) -> None:
        self.db = connect()
        self.addCleanup(self.db.close)
        self.addCleanup(self.db.rollback)
        self.tag = "w10_" + uuid.uuid4().hex[:20]
        if not hasattr(self, "events"):
            self.events: list[dict[str, object]] = []
        self.assertIsNotNone(
            self.db.execute("SELECT OBJECT_ID('w10.fn_OrderDiscount')").fetchone()[0],
            "Install the Week 10 extension in the selected database",
        )
        self.user_id = self.insert_id(
            "INSERT dbo.Users(username,password_hash,email) VALUES(?,?,?);",
            self.tag,
            "fixture-unusable",
            self.tag + "@example.invalid",
        )
        self.tokens: dict[str, bytes] = {}
        self.employees: dict[str, int] = {}
        for role in ("customer", "staff", "admin"):
            identity, kind = self.user_id, "customer"
            if role != "customer":
                row = self.db.execute(
                    "SELECT TOP(1) e.employee_id FROM dbo.Employees e JOIN dbo.Roles r "
                    "ON r.role_id=e.role_id WHERE e.status='active' AND r.role_name=? "
                    "ORDER BY e.employee_id",
                    role,
                ).fetchone()
                self.assertIsNotNone(row, f"Active {role} fixture required")
                identity, kind = int(row[0]), "employee"
                self.employees[role] = identity
            token = uuid.uuid4().bytes + uuid.uuid4().bytes
            self.tokens[role] = token
            self.db.execute("EXEC app.StartSession ?,?,?", kind, identity, token).fetchall()
        self.product_id = self.product("30.00")
        self.account_id = self.insert_id(
            "INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,safety_threshold,created_at) "
            "VALUES('Other',?,'fixture-unusable',1000,200,DATEADD(SECOND,-1,SYSDATETIME()));",
            self.tag,
        )

    def insert_id(self, statement: str, *parameters: object) -> int:
        return int(
            self.db.execute(
                "SET NOCOUNT ON; " + statement + " SELECT CONVERT(INT,SCOPE_IDENTITY());",
                *parameters,
            ).fetchone()[0]
        )

    def product(self, price: str, tokens: int | None = None, provider: str = "Other") -> int:
        if tokens is None:
            tokens = 1_000_000_000 + uuid.uuid4().int % 1_000_000_000
        return self.insert_id(
            "INSERT dbo.Products(name,price,model_provider,token_amount,required_upstream_tokens,status) "
            "VALUES(?,?,?,?,100,'active');",
            self.tag + " product " + uuid.uuid4().hex[:5],
            price,
            provider,
            tokens,
        )

    def api(
        self,
        role: str | None,
        operation: str,
        payload: dict[str, object] | None = None,
        *,
        week10: bool = False,
    ) -> dict[str, object]:
        name = "app.Week10" if week10 else "app.[Execute]"
        try:
            cursor = self.db.execute(
                f"EXEC {name} @token_hash=?,@operation=?,@payload=?",
                self.tokens[role] if role else None,
                operation,
                json.dumps(payload or {}),
            )
        except pyodbc.Error as exc:
            self.events.append(
                {
                    "operation": operation,
                    "role": role,
                    "input": payload or {},
                    "exception": str(exc),
                }
            )
            raise
        self.assertEqual([column[0] for column in cursor.description], ["data"])
        rows = cursor.fetchall()
        self.assertEqual(len(rows), 1)
        result = json.loads(rows[0][0])
        self.events.append(
            {"operation": operation, "role": role, "input": payload or {}, "actual": result}
        )
        self.assertFalse(cursor.nextset(), "Internal result sets must stay inside the boundary")
        self.assertIsInstance(result, dict)
        return result

    def order(self, items: list[tuple[int, int]]) -> int:
        result = self.api(
            "customer",
            "orders.create",
            {
                "items": [
                    {"product_id": product, "quantity": quantity} for product, quantity in items
                ]
            },
        )
        return int(result["order_id"])

    def pricing(self, order_id: int) -> tuple[object, ...]:
        return tuple(
            self.db.execute(
                "SELECT SUM(original_subtotal),SUM(discount_amount),SUM(subtotal) "
                "FROM dbo.OrderDetails WHERE order_id=?",
                order_id,
            ).fetchone()
        )

    def adjustment(
        self, amount: int | None, key: str | None = None, reason: str = "fixture adjustment"
    ) -> dict[str, object]:
        return self.api(
            "admin",
            "inventory.adjustments.create",
            {
                "product_id": self.product_id,
                "account_id": self.account_id,
                "change_amount": amount,
                "reason": reason,
                "operation_key": key or str(uuid.uuid4()),
            },
            week10=True,
        )

    def stock(self) -> tuple[object, ...]:
        return tuple(
            self.db.execute(
                "SELECT a.total_quota,a.used_quota,i.current_quota,"
                "(SELECT COUNT(*) FROM dbo.InventoryLog WHERE account_id=a.account_id),"
                "(SELECT COUNT(*) FROM w10.InventoryAdjustments WHERE account_id=a.account_id) "
                "FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id "
                "WHERE a.account_id=?",
                self.account_id,
            ).fetchone()
        )

    def test_discount_thresholds_and_invalid_values(self) -> None:
        for gross, rate, discount in (
            ("0", "0", "0"),
            ("99.99", "0", "0"),
            ("100", ".05", "5"),
            ("499.99", ".05", "25"),
            ("500", ".10", "50"),
            ("9999999999999999.99", ".10", "1000000000000000.00"),
        ):
            with self.subTest(gross=gross):
                row = self.db.execute("SELECT * FROM w10.fn_OrderDiscount(?)", gross).fetchone()
                self.assertEqual(tuple(row), (Decimal(rate), Decimal(discount)))
        for invalid in (None, "-0.01"):
            self.assertEqual(
                self.db.execute("SELECT * FROM w10.fn_OrderDiscount(?)", invalid).fetchall(), []
            )

    def test_replenishment_boundaries_defaults_and_invalid_values(self) -> None:
        for current, minimum, target, expected in (
            (100, 200, 1000, 900),
            (200, 200, 1000, 0),
            (1000, 200, 1000, 0),
            (100, None, 1000, 900),
            (100, -1, 1000, None),
            (100, 200, 199, None),
            (100, 200, None, None),
        ):
            with self.subTest(current=current, minimum=minimum, target=target):
                self.db.execute(
                    "UPDATE dbo.UpstreamAccount SET total_quota=? WHERE account_id=?",
                    current,
                    self.account_id,
                )
                self.db.execute(
                    "UPDATE dbo.Inventory SET current_quota=? WHERE account_id=?",
                    current,
                    self.account_id,
                )
                actual = self.db.execute(
                    "SELECT w10.fn_ReplenishmentQuantity(?,?,?,?)",
                    self.product_id,
                    self.account_id,
                    minimum,
                    target,
                ).fetchone()[0]
                self.assertEqual(actual, expected)
        for product, account in ((-1, self.account_id), (self.product_id, -1)):
            self.assertIsNone(
                self.db.execute(
                    "SELECT w10.fn_ReplenishmentQuantity(?,?,200,1000)", product, account
                ).fetchone()[0]
            )
        self.db.execute(
            "UPDATE dbo.Products SET model_provider='OpenAI' WHERE product_id=?", self.product_id
        )
        self.assertIsNone(
            self.db.execute(
                "SELECT w10.fn_ReplenishmentQuantity(?,?,200,1000)",
                self.product_id,
                self.account_id,
            ).fetchone()[0]
        )

    def test_rounding_is_per_line(self) -> None:
        first, second = self.product("0.10"), self.product("99.90")
        oid = self.order([(first, 1), (second, 1)])
        self.assertEqual(self.pricing(oid), (Decimal("100"), Decimal("5.01"), Decimal("94.99")))
        rows = self.db.execute(
            "SELECT discount_amount FROM dbo.OrderDetails WHERE order_id=? ORDER BY product_id", oid
        ).fetchall()
        self.assertEqual([row[0] for row in rows], [Decimal(".01"), Decimal("5.00")])

    def test_draft_repricing_add_set_delete_and_price_snapshot(self) -> None:
        oid = self.order([(self.product_id, 3)])
        self.assertEqual(self.pricing(oid), (Decimal(90), Decimal(0), Decimal(90)))
        self.db.execute("UPDATE dbo.Products SET price=99 WHERE product_id=?", self.product_id)
        self.api(
            "customer",
            "orders.item_add",
            {"order_id": oid, "product_id": self.product_id, "quantity": 1},
        )
        self.assertEqual(self.pricing(oid), (Decimal(120), Decimal(6), Decimal(114)))
        item = self.db.execute(
            "SELECT detail_id,unit_price,pricing_rule_version FROM dbo.OrderDetails WHERE order_id=?",
            oid,
        ).fetchone()
        self.assertEqual(tuple(item)[1:], (Decimal(30), "amount-v1"))
        self.api(
            "customer", "orders.item_set", {"order_id": oid, "detail_id": item[0], "quantity": 3}
        )
        self.assertEqual(self.pricing(oid), (Decimal(90), Decimal(0), Decimal(90)))
        self.api("customer", "orders.item_delete", {"order_id": oid, "detail_id": item[0]})
        self.assertEqual(
            tuple(
                self.db.execute(
                    "SELECT total_amount,total_tokens FROM dbo.Orders WHERE order_id=?", oid
                ).fetchone()
            ),
            (Decimal(0), 0),
        )

    def test_legacy_draft_preserves_zero_discount(self) -> None:
        oid = self.order([(self.product_id, 1)])
        self.db.execute("UPDATE dbo.Orders SET pricing_rule_version='legacy' WHERE order_id=?", oid)
        self.api(
            "customer",
            "orders.item_add",
            {"order_id": oid, "product_id": self.product_id, "quantity": 3},
        )
        self.assertEqual(self.pricing(oid), (Decimal(120), Decimal(0), Decimal(120)))

    def test_discount_payment_fifo_partial_refund_and_repeat_refund(self) -> None:
        provider = self.db.execute(
            "SELECT TOP(1) provider FROM (VALUES('Other'),('Gemini'),('Claude'),('OpenAI')) p(provider) "
            "WHERE NOT EXISTS(SELECT 1 FROM dbo.Products WHERE model_provider=p.provider AND token_amount=200000)"
        ).fetchone()[0]
        product = self.product("200", 200000, provider)
        self.db.execute(
            "UPDATE dbo.UpstreamAccount SET provider=? WHERE account_id=?",
            provider,
            self.account_id,
        )
        oid = self.order([(product, 1)])
        self.api("customer", "orders.pay", {"order_id": oid})
        frozen = self.pricing(oid)
        self.assertEqual(frozen, (Decimal(200), Decimal(10), Decimal(190)))
        second = self.order([(product, 1)])
        self.api("customer", "orders.pay", {"order_id": second})
        self.api("customer", "usage.create", {"product_id": product, "tokens_used": 50000})
        lots = self.db.execute(
            "SELECT d.order_id,l.issued_tokens,l.consumed_tokens FROM dbo.OrderTokenLots l "
            "JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id WHERE d.order_id IN(?,?) ORDER BY d.order_id",
            oid,
            second,
        ).fetchall()
        self.assertEqual([tuple(row) for row in lots], [(oid, 200000, 50000), (second, 200000, 0)])
        self.api("customer", "refunds.request", {"order_id": oid})
        self.api("customer", "refunds.request", {"order_id": oid})
        refund = self.db.execute(
            "SELECT refund_amount,refundable_tokens,consumed_tokens FROM dbo.RefundLedger WHERE order_id=?",
            oid,
        ).fetchall()
        self.assertEqual([tuple(row) for row in refund], [(Decimal("142.50"), 150000, 50000)])
        self.assertEqual(self.pricing(oid), frozen)
        balance = self.db.execute(
            "SELECT remaining_tokens FROM dbo.TokenBalances WHERE user_id=? AND model_provider=?",
            self.user_id,
            provider,
        ).fetchone()[0]
        self.assertEqual(balance, 200000)

    def test_sales_two_results_distinct_orders_refunded_and_pending(self) -> None:
        self.db.execute("UPDATE dbo.Users SET created_at='20000101' WHERE user_id=?", self.user_id)
        q = self.product("40")
        first = self.order([(self.product_id, 2), (q, 1)])
        second = self.order([(self.product_id, 1)])
        pending = self.order([(q, 9)])
        cancelled = self.order([(q, 9)])
        self.api("staff", "orders.cancel", {"order_id": cancelled})
        for oid in (first, second):
            self.api("customer", "orders.pay", {"order_id": oid})
        self.api("customer", "refunds.request", {"order_id": first})
        # Move only our fixture orders to a quiet historical date, preserving payment ordering.
        self.db.execute(
            "UPDATE dbo.Orders SET created_at='20010203',paid_at='20010203' WHERE order_id IN(?,?)",
            first,
            second,
        )
        cursor = self.db.execute("EXEC w10.usp_SalesStatistics '20010203','20010203'")
        self.assertEqual(tuple(cursor.fetchone()), (2, 4, Decimal(125)))
        self.assertTrue(cursor.nextset())
        actual = {
            row.product_id: (row.sales_quantity, row.sales_amount, row.order_count)
            for row in cursor.fetchall()
        }
        self.assertEqual(actual, {self.product_id: (3, Decimal(87), 2), q: (1, Decimal(38), 1)})
        self.assertFalse(cursor.nextset())
        tvf = self.db.execute(
            "SELECT product_id,sales_quantity,sales_amount,order_count FROM w10.fn_SalesSummary('20010203','20010203')"
        ).fetchall()
        self.assertEqual({row[0]: tuple(row)[1:] for row in tvf}, actual)
        self.assertEqual(
            self.db.execute("SELECT status FROM dbo.Orders WHERE order_id=?", pending).fetchone()[
                0
            ],
            "pending",
        )

    def test_sales_empty_invalid_and_maximum_end_date(self) -> None:
        cursor = self.db.execute("EXEC w10.usp_SalesStatistics '00010101','00010101'")
        self.assertEqual(tuple(cursor.fetchone()), (0, 0, Decimal(0)))
        self.assertTrue(cursor.nextset())
        self.assertEqual(cursor.fetchall(), [])
        for start, end in ((None, "2026-01-01"), ("2026-01-02", "2026-01-01")):
            self.assertEqual(
                self.db.execute("SELECT * FROM w10.fn_SalesSummary(?,?)", start, end).fetchall(), []
            )
            with self.assertRaisesRegex(pyodbc.Error, "56000"):
                self.db.execute("EXEC w10.usp_SalesStatistics ?,?", start, end)
        cursor = self.db.execute("EXEC w10.usp_SalesStatistics '99991231','99991231'")
        self.assertEqual(tuple(cursor.fetchone()), (0, 0, Decimal(0)))
        cursor.nextset()
        self.assertEqual(cursor.fetchall(), [])

    def test_sales_inclusive_dates_use_payment_time(self) -> None:
        self.db.execute("UPDATE dbo.Users SET created_at='20000101' WHERE user_id=?", self.user_id)
        ids = [self.order([(self.product_id, 1)]) for _ in range(3)]
        for oid, paid_at in zip(
            ids, ("2001-02-03T00:00:00", "2001-02-04T23:59:59", "2001-02-05T00:00:00"), strict=True
        ):
            self.api("customer", "orders.pay", {"order_id": oid})
            self.db.execute(
                "UPDATE dbo.Orders SET created_at='20010101',paid_at=? WHERE order_id=?",
                paid_at,
                oid,
            )
        cursor = self.db.execute("EXEC w10.usp_SalesStatistics '20010203','20010204'")
        self.assertEqual(tuple(cursor.fetchone()), (2, 2, Decimal(60)))
        cursor.nextset()
        self.assertEqual(len(cursor.fetchall()), 1)

    def test_adjustment_audit_and_same_key_idempotency(self) -> None:
        self.db.execute(
            "UPDATE dbo.UpstreamAccount SET total_quota=1200,used_quota=200 WHERE account_id=?",
            self.account_id,
        )
        key = str(uuid.uuid4())
        first = self.adjustment(300, key)
        again = self.adjustment(300, key)
        self.assertEqual(first, again)
        self.assertEqual(self.stock()[:3], (1500, 200, 1300))
        self.adjustment(-400)
        self.assertEqual(self.stock()[:3], (1100, 200, 900))
        rows = self.db.execute(
            "SELECT a.change_amount,l.change_amount,l.change_type,l.reference_type,l.reference_id "
            "FROM w10.InventoryAdjustments a JOIN dbo.InventoryLog l ON l.log_id=a.log_id WHERE a.account_id=? ORDER BY a.adjustment_id",
            self.account_id,
        ).fetchall()
        self.assertEqual(
            [tuple(row) for row in rows],
            [(300, 300, "adjustment", "manual", None), (-400, -400, "adjustment", "manual", None)],
        )

    def test_invalid_quantity_and_reason_do_not_write(self) -> None:
        for amount, reason in (
            (0, "valid"),
            (None, "valid"),
            (1, ""),
            (1, " " * 5),
            (1, "x" * 256),
        ):
            with self.subTest(amount=amount, reason_length=len(reason)):
                if amount != 0:
                    self.db.rollback()
                    self.setUp()
                with self.assertRaisesRegex(pyodbc.Error, "56000"):
                    self.adjustment(amount, reason=reason)
                self.assertEqual(
                    self.db.execute(
                        "SELECT COUNT(*) FROM w10.InventoryAdjustments WHERE account_id=?",
                        self.account_id,
                    ).fetchone()[0],
                    0,
                )

    def test_operation_key_parameter_conflict_rolls_back(self) -> None:
        key = str(uuid.uuid4())
        self.adjustment(10, key)
        with self.assertRaisesRegex(pyodbc.Error, "56009"):
            self.adjustment(11, key)
        # The procedure rolls back its caller's transaction after an error.
        self.assertEqual(
            self.db.execute(
                "SELECT COUNT(*) FROM w10.InventoryAdjustments WHERE operation_key=?", key
            ).fetchone()[0],
            0,
        )
        self.assertEqual(
            self.db.execute(
                "SELECT COUNT(*) FROM dbo.UpstreamAccount WHERE account_name=?", self.tag
            ).fetchone()[0],
            0,
        )

    def test_invalid_account_product_operator_and_pair_are_rejected(self) -> None:
        cases = ("product", "account", "staff", "suspended", "expired", "mismatch", "inconsistent")
        for index, case in enumerate(cases):
            with self.subTest(case=case):
                if index:
                    self.db.rollback()
                    self.setUp()
                product, account, operator = (
                    self.product_id,
                    self.account_id,
                    self.employees["admin"],
                )
                expected = "56009"
                if case == "product":
                    product, expected = -1, "56000"
                elif case == "account":
                    account, expected = 2147483647, "56004"
                elif case == "staff":
                    operator, expected = self.employees["staff"], "56003"
                elif case == "suspended":
                    self.db.execute(
                        "UPDATE dbo.UpstreamAccount SET status='suspended' WHERE account_id=?",
                        account,
                    )
                elif case == "expired":
                    self.db.execute(
                        "UPDATE dbo.UpstreamAccount SET created_at=DATEADD(DAY,-2,SYSDATETIME()),expires_at=DATEADD(DAY,-1,SYSDATETIME()) WHERE account_id=?",
                        account,
                    )
                elif case == "mismatch":
                    self.db.execute(
                        "UPDATE dbo.Products SET model_provider='OpenAI' WHERE product_id=?",
                        product,
                    )
                    expected = "56000"
                else:
                    self.db.execute(
                        "UPDATE dbo.Inventory SET current_quota=999 WHERE account_id=?", account
                    )
                with self.assertRaisesRegex(pyodbc.Error, expected):
                    self.db.execute(
                        "EXEC w10.usp_AdjustInventory ?,?,1,N'test invalid',?,?",
                        product,
                        account,
                        operator,
                        str(uuid.uuid4()),
                    )
                self.assertEqual(
                    self.db.execute(
                        "SELECT COUNT(*) FROM w10.InventoryAdjustments WHERE account_id=?",
                        self.account_id,
                    ).fetchone()[0],
                    0,
                )

    def test_draft_amount_overflow_rolls_back_without_partial_order(self) -> None:
        with self.assertRaisesRegex(pyodbc.Error, r"8115|56000"):
            self.order([(self.product_id, 2147483647)])
        self.assertEqual(
            self.db.execute(
                "SELECT COUNT(*) FROM dbo.Orders WHERE user_id=?", self.user_id
            ).fetchone()[0],
            0,
        )
        self.assertEqual(
            self.db.execute(
                "SELECT COUNT(*) FROM dbo.OrderDetails WHERE product_id=?", self.product_id
            ).fetchone()[0],
            0,
        )

    def test_duplicate_json_fields_are_rejected_at_runtime_boundary(self) -> None:
        payload = (
            f'{{"product_id":{self.product_id},"product_id":{self.product_id},'
            f'"account_id":{self.account_id},"target_quota":3000}}'
        )
        self.db.execute(
            "CREATE USER week10_duplicate_probe WITHOUT LOGIN; ALTER ROLE app_runtime ADD MEMBER week10_duplicate_probe; EXECUTE AS USER='week10_duplicate_probe';"
        )
        try:
            with self.assertRaisesRegex(pyodbc.Error, "56000"):
                self.db.execute(
                    "EXEC app.Week10 @token_hash=?,@operation='restocks.recommendation',@payload=?",
                    self.tokens["admin"],
                    payload,
                )
        finally:
            self.db.execute("REVERT")
        self.assertEqual(
            self.db.execute(
                "SELECT COUNT(*) FROM w10.InventoryAdjustments WHERE account_id=?", self.account_id
            ).fetchone()[0],
            0,
        )

    def test_underflow_and_bigint_extremes_roll_back(self) -> None:
        for amount in (-1001, -(2**63), 2**63 - 1):
            with self.subTest(amount=amount):
                # Each rejected call destroys the fixture transaction, recreate it for the next case.
                if amount != -1001:
                    self.db.rollback()
                    self.setUp()
                account_id = self.account_id
                with self.assertRaisesRegex(pyodbc.Error, "56009"):
                    self.adjustment(amount)
                self.assertEqual(
                    self.db.execute(
                        "SELECT COUNT(*) FROM dbo.InventoryLog WHERE account_id=?", account_id
                    ).fetchone()[0],
                    0,
                )
                self.assertEqual(
                    self.db.execute(
                        "SELECT COUNT(*) FROM w10.InventoryAdjustments WHERE account_id=?",
                        account_id,
                    ).fetchone()[0],
                    0,
                )

    def test_week10_authorization_and_forged_actor(self) -> None:
        for role, operation, payload, error in (
            (None, "reports.sales", {}, "56001"),
            ("customer", "reports.sales", {}, "56003"),
            ("staff", "inventory.adjustments.create", {}, "56003"),
            ("admin", "reports.sales", {"operator_id": self.employees["staff"]}, "56000"),
            ("admin", "reports.sales", {"discount_rate": ".5"}, "56000"),
        ):
            with self.subTest(role=role, operation=operation):
                if role is not None:
                    self.db.rollback()
                    self.setUp()
                with self.assertRaisesRegex(pyodbc.Error, error):
                    self.api(role, operation, payload, week10=True)
                self.assertEqual(
                    self.db.execute(
                        "SELECT COUNT(*) FROM w10.InventoryAdjustments WHERE account_id=?",
                        self.account_id,
                    ).fetchone()[0],
                    0,
                )

    def test_week10_app_json_and_strict_dates(self) -> None:
        result = self.api(
            "staff",
            "reports.sales",
            {"start_date": "0001-01-01", "end_date": "0001-01-01"},
            week10=True,
        )
        self.assertEqual(
            result,
            {"summary": {"order_count": 0, "sales_quantity": 0, "sales_amount": 0}, "items": []},
        )
        for start in ("2026-1-01", "2026-01-01 ", "invalid", None):
            self.db.rollback()
            self.setUp()
            with self.assertRaisesRegex(pyodbc.Error, "56000"):
                self.api(
                    "staff",
                    "reports.sales",
                    {"start_date": start, "end_date": "2026-01-01"},
                    week10=True,
                )
        self.db.rollback()
        self.setUp()
        result = self.api(
            "staff",
            "restocks.recommendation",
            {
                "product_id": self.product_id,
                "account_id": self.account_id,
                "minimum_quota": 2000,
                "target_quota": 3000,
            },
            week10=True,
        )
        self.assertEqual(result, {"recommended_quantity": 2000})

    def test_runtime_cannot_execute_internal_week10_objects(self) -> None:
        self.db.execute(
            "CREATE USER week10_permission_probe WITHOUT LOGIN; ALTER ROLE app_runtime ADD MEMBER week10_permission_probe; SET XACT_ABORT OFF; EXECUTE AS USER='week10_permission_probe';"
        )
        try:
            for statement in (
                "SELECT * FROM w10.InventoryAdjustments",
                "SELECT * FROM w10.fn_OrderDiscount(100)",
                "EXEC w10.usp_SalesStatistics '20260101','20260101'",
                "EXEC w10.usp_RepriceDraft -1",
                "INSERT w10.InventoryAdjustments DEFAULT VALUES",
                "UPDATE w10.InventoryAdjustments SET reason=reason WHERE 1=0",
                "DELETE w10.InventoryAdjustments WHERE 1=0",
            ):
                with self.subTest(statement=statement):
                    with self.assertRaisesRegex(pyodbc.Error, r"\(229\)"):
                        self.db.execute(statement)
        finally:
            self.db.execute("REVERT")

    def test_runtime_boundary_rejects_forged_fields_and_structured_quotas(self) -> None:
        for index, (operation, extra, week10, error) in enumerate(
            (
                ("restocks.recommendation", {"minimum_quota": {}}, True, "56000"),
                ("restocks.recommendation", {"minimum_quota": []}, True, "56000"),
                ("restocks.recommendation", {"operator_id": 1}, True, "56000"),
                ("restocks.recommendation", {"price": "1"}, True, "56000"),
                ("orders.create", {"discount_rate": ".5"}, False, "56000"),
                ("orders.create", {"total_amount": "1"}, False, "56000"),
            )
        ):
            with self.subTest(operation=operation, extra=extra):
                if index:
                    self.db.rollback()
                    self.setUp()
                payload: dict[str, object] = {
                    "product_id": self.product_id,
                    "account_id": self.account_id,
                    "target_quota": "3000",
                    "items": [{"product_id": self.product_id, "quantity": 1}],
                }
                if week10:
                    payload.pop("items")
                else:
                    for key in ("product_id", "account_id", "target_quota"):
                        payload.pop(key)
                payload.update(extra)
                self.db.execute(
                    "CREATE USER week10_boundary_probe WITHOUT LOGIN; ALTER ROLE app_runtime ADD MEMBER week10_boundary_probe; EXECUTE AS USER='week10_boundary_probe';"
                )
                try:
                    with self.assertRaisesRegex(pyodbc.Error, error):
                        self.api(
                            "admin" if week10 else "customer", operation, payload, week10=week10
                        )
                finally:
                    self.db.execute("REVERT")

    def test_payment_lot_failure_rolls_back_order_balance_and_lots(self) -> None:
        oid = self.order([(self.product_id, 4)])
        trigger = "dbo.test_fail_" + uuid.uuid4().hex
        self.db.execute(
            f"CREATE TRIGGER {trigger} ON dbo.OrderTokenLots AFTER INSERT AS THROW 56998,'injected lot failure',1;"
        )
        with self.assertRaisesRegex(pyodbc.Error, "56998"):
            self.api("customer", "orders.pay", {"order_id": oid})
        self.assertEqual(
            self.db.execute("SELECT COUNT(*) FROM dbo.Orders WHERE order_id=?", oid).fetchone()[0],
            0,
        )
        self.assertEqual(
            self.db.execute(
                "SELECT COUNT(*) FROM dbo.TokenBalances WHERE user_id=?", self.user_id
            ).fetchone()[0],
            0,
        )
        self.assertEqual(
            self.db.execute(
                "SELECT COUNT(*) FROM dbo.OrderTokenLots l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id WHERE d.order_id=?",
                oid,
            ).fetchone()[0],
            0,
        )
        self.assertIsNone(self.db.execute("SELECT OBJECT_ID(?)", trigger).fetchone()[0])

    def test_refund_ledger_failure_rolls_back_balance_lots_and_refund(self) -> None:
        oid = self.order([(self.product_id, 4)])
        self.api("customer", "orders.pay", {"order_id": oid})
        trigger = "dbo.test_fail_" + uuid.uuid4().hex
        self.db.execute(
            f"CREATE TRIGGER {trigger} ON dbo.RefundLedger AFTER INSERT AS THROW 56997,'injected refund failure',1;"
        )
        with self.assertRaisesRegex(pyodbc.Error, "56997"):
            self.api("customer", "refunds.request", {"order_id": oid})
        self.assertEqual(
            self.db.execute(
                "SELECT COUNT(*) FROM dbo.RefundLedger WHERE order_id=?", oid
            ).fetchone()[0],
            0,
        )
        self.assertEqual(
            self.db.execute(
                "SELECT COUNT(*) FROM dbo.TokenBalances WHERE user_id=?", self.user_id
            ).fetchone()[0],
            0,
        )
        self.assertEqual(
            self.db.execute(
                "SELECT COUNT(*) FROM dbo.OrderTokenLots l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id WHERE d.order_id=?",
                oid,
            ).fetchone()[0],
            0,
        )
        self.assertIsNone(self.db.execute("SELECT OBJECT_ID(?)", trigger).fetchone()[0])

    def test_adjustment_ledger_failure_rolls_back_four_tables(self) -> None:
        trigger = "w10.test_fail_" + uuid.uuid4().hex
        self.db.execute(
            f"CREATE TRIGGER {trigger} ON w10.InventoryAdjustments AFTER INSERT AS THROW 56999,'injected ledger failure',1;"
        )
        account_id = self.account_id
        with self.assertRaisesRegex(pyodbc.Error, "56999"):
            self.adjustment(5)
        for table in (
            "dbo.UpstreamAccount",
            "dbo.Inventory",
            "dbo.InventoryLog",
            "w10.InventoryAdjustments",
        ):
            with self.subTest(table=table):
                self.assertEqual(
                    self.db.execute(
                        f"SELECT COUNT(*) FROM {table} WHERE account_id=?", account_id
                    ).fetchone()[0],
                    0,
                )
        self.assertIsNone(self.db.execute("SELECT OBJECT_ID(?)", trigger).fetchone()[0])

    def test_two_connections_same_key_and_competing_debits(self) -> None:
        # A committed account is necessary for both independent connections to see it.
        # Tagged fixtures remain in this explicitly disposable database for audit inspection.
        self.db.commit()
        key = str(uuid.uuid4())

        def run(amount: int, operation_key: str) -> tuple[bool, int | str]:
            db = connect()
            try:
                row = db.execute(
                    "EXEC w10.usp_AdjustInventory ?,?,?,?, ?,?",
                    self.product_id,
                    self.account_id,
                    amount,
                    self.tag,
                    self.employees["admin"],
                    operation_key,
                ).fetchone()
                db.commit()
                return True, int(row.adjustment_id)
            except pyodbc.Error as exc:
                db.rollback()
                return False, str(exc)
            finally:
                db.close()

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: run(10, key), range(2)))
        self.assertTrue(all(result[0] for result in results), results)
        self.assertEqual(results[0][1], results[1][1])
        self.assertEqual(self.stock()[:3], (1010, 0, 1010))
        self.db.rollback()
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: run(-600, str(uuid.uuid4())), range(2)))
        self.assertEqual(sum(result[0] for result in results), 1, results)
        self.assertIn("56009", str([result[1] for result in results if not result[0]]))
        self.assertEqual(self.stock()[:3], (410, 0, 410))
        self.assertEqual(self.stock()[4], 2)

    def test_two_connections_payment_credits_exactly_once(self) -> None:
        oid = self.order([(self.product_id, 4)])
        expected_tokens = self.db.execute(
            "SELECT total_tokens FROM dbo.Orders WHERE order_id=?", oid
        ).fetchone()[0]
        self.db.commit()

        def pay(_: int) -> tuple[bool, str]:
            db = connect()
            try:
                row = db.execute(
                    "EXEC app.[Execute] @token_hash=?,@operation='orders.pay',@payload=?",
                    self.tokens["customer"],
                    json.dumps({"order_id": oid}),
                ).fetchone()
                db.commit()
                return True, str(row[0])
            except pyodbc.Error as exc:
                db.rollback()
                return False, str(exc)
            finally:
                db.close()

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(pay, range(2)))
        self.assertEqual(sum(result[0] for result in results), 1, str(results))
        self.assertIn("55009", str([result[1] for result in results if not result[0]]))
        self.assertEqual(
            self.db.execute(
                "SELECT remaining_tokens FROM dbo.TokenBalances WHERE user_id=? AND model_provider='Other'",
                self.user_id,
            ).fetchone()[0],
            expected_tokens,
        )
        self.assertEqual(
            tuple(
                self.db.execute(
                    "SELECT COUNT(*),SUM(l.issued_tokens),SUM(l.consumed_tokens) FROM dbo.OrderTokenLots l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id WHERE d.order_id=?",
                    oid,
                ).fetchone()
            ),
            (1, expected_tokens, 0),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
