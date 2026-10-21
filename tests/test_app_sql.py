"""Isolated app SQL contract and rollback-only SQL Server regressions."""

import os
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATABASE = os.environ.get("DB_LAB_APP_DATABASE", "")
SERVER = os.environ.get("DB_LAB_TEST_SERVER", r"localhost\SQLEXPRESS")


class AppSqlSourceTests(unittest.TestCase):
    def test_guard_and_narrow_public_grants(self) -> None:
        source = (ROOT / "sql/app/install.sql").read_text(encoding="utf-8")
        self.assertIn("TokenHubDB[_]v11[_]Web%", source)
        self.assertIn("SCHEMA_ID(N'app') IS NOT NULL", source)
        self.assertNotRegex(source, r"(?i)GRANT\s+(SELECT|INSERT|UPDATE|DELETE|ALTER|CONTROL)")
        self.assertNotRegex(source, r"(?i)GRANT EXECUTE ON SCHEMA")
        self.assertNotRegex(source, r"(?i)EXEC(?:UTE)?\s*\(@")
        for name in ("AuthLookup", "StartSession", "ResolveSession", "EndSession", "Execute"):
            identifier = "[Execute]" if name == "Execute" else name
            self.assertIn(f"GRANT EXECUTE ON app.{identifier} TO app_runtime", source)


@unittest.skipUnless(DATABASE, "Set DB_LAB_APP_DATABASE to an isolated installed app database")
class AppSqlWorkflowTests(unittest.TestCase):
    """Exercise the real procedure boundary; every fixture transaction is rolled back."""

    def setUp(self) -> None:
        import uuid

        import pyodbc

        self.assertRegex(DATABASE, r"^TokenHubDB_v11_Web[A-Za-z0-9_]*$")
        self.connection = pyodbc.connect(
            f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};"
            "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;",
            autocommit=False,
        )
        self.addCleanup(self.connection.close)
        self.addCleanup(self.connection.rollback)
        self.tag = uuid.uuid4().hex[:16]
        cur = self.connection.cursor()
        row = cur.execute(
            "SET NOCOUNT ON; INSERT dbo.Users(username,password_hash,email) VALUES(?,?,?); SELECT CONVERT(INT,SCOPE_IDENTITY())",
            "test_" + self.tag,
            "fixture-unusable",
            self.tag + "@example.invalid",
        ).fetchone()
        self.user_id = int(row[0])
        self.tokens: dict[str, bytes] = {}
        for role in ("customer", "staff", "admin"):
            if role == "customer":
                identity, kind = self.user_id, "customer"
            else:
                found = cur.execute(
                    "SELECT TOP(1) e.employee_id FROM dbo.Employees e JOIN dbo.Roles r "
                    "ON r.role_id=e.role_id WHERE r.role_name=? AND e.status='active' ORDER BY e.employee_id",
                    role,
                ).fetchone()
                self.assertIsNotNone(found, f"Active {role} fixture required")
                identity, kind = int(found[0]), "employee"
            token = uuid.uuid4().bytes + uuid.uuid4().bytes
            self.tokens[role] = token
            cur.execute("EXEC app.StartSession ?,?,?", kind, identity, token).fetchall()
        self.product_tokens = 2_000_000_000 + int(self.tag[:5], 16)
        self.product_id = int(
            cur.execute(
                "SET NOCOUNT ON; INSERT dbo.Products(name,price,model_provider,token_amount,required_upstream_tokens,status) "
                "VALUES(?,1.25,'Other',?,3,'active'); SELECT CONVERT(INT,SCOPE_IDENTITY())",
                "Fixture " + self.tag,
                self.product_tokens,
            ).fetchone()[0]
        )
        self.account_id = int(
            cur.execute(
                "SET NOCOUNT ON; INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,safety_threshold) "
                "VALUES('Other',?,'fixture-unusable',10000,10); SELECT CONVERT(INT,SCOPE_IDENTITY())",
                self.tag,
            ).fetchone()[0]
        )

    def api(
        self, role: str | None, operation: str, payload: dict[str, object] | None = None
    ) -> dict[str, object]:
        import json

        cursor = self.connection.cursor().execute(
            "EXEC app.[Execute] @token_hash=?,@operation=?,@payload=?",
            self.tokens[role] if role else None,
            operation,
            json.dumps(payload or {}),
        )
        self.assertEqual([c[0] for c in cursor.description], ["data"])
        rows = cursor.fetchall()
        self.assertEqual(len(rows), 1)
        result = json.loads(rows[0][0])
        self.assertFalse(cursor.nextset(), "Legacy procedure result set leaked")
        self.assertIsInstance(result, dict)
        return result

    def test_order_usage_refund_lifecycle_and_exact_ceiling(self) -> None:
        order = self.api(
            "customer",
            "orders.create",
            {
                "items": [
                    {"product_id": self.product_id, "quantity": 1},
                    {"product_id": self.product_id, "quantity": 2},
                ]
            },
        )
        oid = order["order_id"]
        detail = self.api("customer", "orders.get", {"order_id": oid})
        self.assertEqual(detail["items"][0]["quantity"], 3)
        did = detail["items"][0]["detail_id"]
        self.api(
            "customer",
            "orders.item_add",
            {"order_id": oid, "product_id": self.product_id, "quantity": 1},
        )
        self.api("customer", "orders.item_set", {"order_id": oid, "detail_id": did, "quantity": 2})
        self.api("customer", "orders.item_delete", {"order_id": oid, "detail_id": did})
        empty = self.api("customer", "orders.get", {"order_id": oid})
        self.assertEqual(empty["order"]["total_tokens"], 0)
        self.assertEqual(empty["order"]["total_amount"], 0)
        self.api(
            "customer",
            "orders.item_add",
            {"order_id": oid, "product_id": self.product_id, "quantity": 2},
        )
        self.api("customer", "orders.pay", {"order_id": oid})
        usage = self.api(
            "customer",
            "usage.create",
            {"product_id": self.product_id, "tokens_used": 1, "user_id": 1, "account_id": -1},
        )
        row = (
            self.connection.cursor()
            .execute(
                "SELECT user_id,upstream_tokens_consumed,api_endpoint FROM dbo.TokenUsageLogs WHERE log_id=?",
                usage["log_id"],
            )
            .fetchone()
        )
        self.assertEqual(tuple(row), (self.user_id, 1, "/simulation"))
        self.api("customer", "refunds.request", {"order_id": oid})
        self.api(
            "admin",
            "refunds.settle",
            {"order_id": oid, "external_payout_ref": "client-supplied-ignored"},
        )
        settled = (
            self.connection.cursor()
            .execute(
                "SELECT payout_state,external_payout_ref FROM dbo.RefundLedger WHERE order_id=?",
                oid,
            )
            .fetchone()
        )
        self.assertEqual(tuple(settled), ("settled", f"SIM-{oid}"))
        for operation in ("orders.list", "usage.list", "balances.list", "refunds.list"):
            result = self.api("customer", operation)
            self.assertEqual(result["page_size"], 20)
            self.assertEqual(result["page"], 1)
            self.assertIsInstance(result["items"], list)

    def test_product_and_account_crud_restock_cancel_delete(self) -> None:
        product = self.api(
            "admin",
            "products.save",
            {
                "name": "Created " + self.tag,
                "description": "Description",
                "price": "2.50",
                "model_provider": "Other",
                "token_amount": "1900000001",
                "required_upstream_tokens": 2,
                "status": "inactive",
            },
        )
        guest = self.api(None, "products.list", {"q": "Created " + self.tag})
        self.assertEqual(guest["total"], 0)
        employee = self.api("staff", "products.list", {"q": "Created " + self.tag})
        self.assertEqual(employee["total"], 1)
        self.api("admin", "products.delete", product)
        fields: dict[str, object] = {
            "provider": "Other",
            "account_name": "Created " + self.tag,
            "total_quota": "500",
            "safety_threshold": "20",
            "status": "active",
            "expires_at": None,
        }
        account = self.api("admin", "accounts.save", fields)
        del fields["total_quota"]
        fields.update(account)
        fields["safety_threshold"] = "30"
        self.api("admin", "accounts.save", fields)
        self.api("admin", "accounts.delete", account)
        inventory = self.api("staff", "inventory.list")
        self.assertNotIn("api_key", str(inventory))
        task = self.api(
            "staff",
            "restocks.create",
            {"account_id": self.account_id, "planned_amount": "250", "created_by": -1},
        )
        self.api("admin", "restocks.complete", {"task_id": task["task_id"], "actual_amount": "300"})
        pair = (
            self.connection.cursor()
            .execute(
                "SELECT a.total_quota,i.current_quota FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id WHERE a.account_id=?",
                self.account_id,
            )
            .fetchone()
        )
        self.assertEqual(tuple(pair), (10300, 10300))
        self.api("staff", "restocks.list")
        order = self.api(
            "customer", "orders.create", {"items": [{"product_id": self.product_id, "quantity": 1}]}
        )
        detail = self.api("customer", "orders.get", order)
        self.api(
            "customer",
            "orders.item_delete",
            {"order_id": order["order_id"], "detail_id": detail["items"][0]["detail_id"]},
        )
        self.api("staff", "orders.cancel", order)
        self.api("admin", "orders.delete", order)

    def test_atomic_create_with_invalid_late_item(self) -> None:
        import pyodbc

        before = self.connection.cursor().execute("SELECT COUNT(*) FROM dbo.Orders").fetchone()[0]
        with self.assertRaisesRegex(pyodbc.Error, "52127"):
            self.api(
                "customer",
                "orders.create",
                {
                    "items": [
                        {"product_id": self.product_id, "quantity": 1},
                        {"product_id": 2147483647, "quantity": 1},
                    ]
                },
            )
        # app errors roll back the entire caller transaction, including fixtures.
        self.assertEqual(
            self.connection.cursor()
            .execute("SELECT COUNT(*) FROM dbo.Orders WHERE user_id=?", self.user_id)
            .fetchone()[0],
            0,
        )
        self.assertLessEqual(
            self.connection.cursor().execute("SELECT COUNT(*) FROM dbo.Orders").fetchone()[0],
            before,
        )

    def test_cross_customer_cannot_modify_order(self) -> None:
        import pyodbc

        other = (
            self.connection.cursor()
            .execute(
                "SELECT TOP(1) user_id FROM dbo.Users WHERE user_id<>? AND status='active'",
                self.user_id,
            )
            .fetchone()[0]
        )
        row = (
            self.connection.cursor()
            .execute(
                "SET NOCOUNT ON; INSERT dbo.Orders(user_id,total_amount,total_tokens,status) VALUES(?,0,0,'pending'); SELECT CONVERT(INT,SCOPE_IDENTITY())",
                other,
            )
            .fetchone()
        )
        with self.assertRaisesRegex(pyodbc.Error, "55003"):
            self.api(
                "customer", "orders.cancel", {"order_id": row[0], "user_id": other, "role": "admin"}
            )

    def test_multiple_pending_refunds_are_independent(self) -> None:
        ids: list[object] = []
        for _ in range(2):
            order = self.api(
                "customer",
                "orders.create",
                {"items": [{"product_id": self.product_id, "quantity": 1}]},
            )
            self.api("customer", "orders.pay", order)
            self.api("customer", "refunds.request", order)
            ids.append(order["order_id"])
        count = (
            self.connection.cursor()
            .execute(
                "SELECT COUNT(*) FROM dbo.RefundLedger WHERE order_id IN(?,?) AND payout_state='awaiting_transfer' AND external_payout_ref IS NULL",
                *ids,
            )
            .fetchone()[0]
        )
        self.assertEqual(count, 2)

    def test_expired_revoked_and_inactive_sessions(self) -> None:
        cursor = self.connection.cursor()
        token = self.tokens["customer"]
        cursor.execute("EXEC app.EndSession ?", token)
        self.assertIsNotNone(
            cursor.execute(
                "SELECT revoked_at FROM app.Sessions WHERE token_hash=?", token
            ).fetchone()[0]
        )
        self.assertEqual(cursor.execute("EXEC app.ResolveSession ?", token).fetchall(), [])
        cursor.execute(
            "UPDATE app.Sessions SET revoked_at=NULL,expires_at=DATEADD(SECOND,-1,SYSDATETIME()) WHERE token_hash=?",
            token,
        )
        self.assertEqual(cursor.execute("EXEC app.ResolveSession ?", token).fetchall(), [])
        cursor.execute(
            "UPDATE app.Sessions SET expires_at=DATEADD(HOUR,1,SYSDATETIME()) WHERE token_hash=?",
            token,
        )
        cursor.execute("UPDATE dbo.Users SET status='frozen' WHERE user_id=?", self.user_id)
        self.assertEqual(cursor.execute("EXEC app.ResolveSession ?", token).fetchall(), [])

    def test_runtime_all_table_dml_and_ddl_denied(self) -> None:
        import pyodbc

        cursor = self.connection.cursor()
        tables = cursor.execute(
            "SELECT s.name,t.name,c.name FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id "
            "CROSS APPLY(SELECT TOP(1) c.name FROM sys.columns c WHERE c.object_id=t.object_id AND c.is_identity=0 AND c.is_computed=0 ORDER BY c.column_id)c WHERE t.is_ms_shipped=0"
        ).fetchall()
        cursor.execute(
            "CREATE USER app_runtime_test WITHOUT LOGIN; ALTER ROLE app_runtime ADD MEMBER app_runtime_test; SET XACT_ABORT OFF; EXECUTE AS USER='app_runtime_test';"
        )
        try:
            for schema, table, column in tables:
                name = f"[{schema}].[{table}]"
                statements = [
                    f"SELECT TOP(0) * FROM {name}",
                    f"INSERT {name} DEFAULT VALUES",
                    f"UPDATE {name} SET [{column}]=[{column}] WHERE 1=0",
                    f"DELETE {name} WHERE 1=0",
                ]
                for statement in statements:
                    with self.subTest(table=name, statement=statement.split()[0]):
                        with self.assertRaisesRegex(pyodbc.Error, r"\(229\)"):
                            cursor.execute(statement)
            for statement in (
                "CREATE TABLE app.permission_probe(id INT)",
                "ALTER TABLE dbo.Products ADD permission_probe INT NULL",
                "DROP TABLE dbo.Products",
                "EXEC dbo.usp_W6_PayPendingOrder @order_id=-1",
            ):
                with self.subTest(statement=statement):
                    with self.assertRaises(pyodbc.Error):
                        cursor.execute(statement)
        finally:
            cursor.execute("REVERT")

    def test_guest_catalog_and_authentication_boundary(self) -> None:
        import pyodbc

        result = self.api(None, "products.list", {"q": "does-not-exist-" + self.tag})
        self.assertEqual(result, {"items": [], "total": 0, "page": 1, "page_size": 20})
        with self.assertRaisesRegex(pyodbc.Error, "55001"):
            self.api(None, "orders.list")

    def test_customer_payload_cannot_elevate_role(self) -> None:
        import pyodbc

        with self.assertRaisesRegex(pyodbc.Error, "55003"):
            self.api("customer", "products.save", {"name": "spoof", "role": "admin", "user_id": 1})

    def test_old_business_error_propagates_without_insert_exec_masking(self) -> None:
        import pyodbc

        with self.assertRaisesRegex(pyodbc.Error, "51956"):
            self.api("customer", "usage.create", {"product_id": self.product_id, "tokens_used": 1})
