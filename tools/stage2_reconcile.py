"""Read-only SQL Server reconciliation for the isolated stage-2 browser run."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suffix", required=True)
    args = parser.parse_args()
    if args.suffix != "WebStage2A02":
        raise SystemExit("Refuse unapproved database / evidence suffix")
    directory = ROOT / "result" / "stage2" / args.suffix
    manifest = json.loads((directory / "browser" / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["result"] == "PASS" and manifest["database"] == "TokenHubDB_v11_" + args.suffix
    screenshots = manifest["screenshots"]
    for picture in screenshots:
        path = directory / "browser" / "screenshots" / picture["file"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == picture["sha256"]
        blob = path.read_bytes()
        assert blob.startswith(b"\x89PNG\r\n\x1a\n") and len(blob) > 48
        width, height = struct.unpack(">II", blob[16:24])
        assert width >= 800 and height >= 500, (path, width, height)
    conn = pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        r"SERVER=localhost\SQLEXPRESS;"
        "DATABASE=TokenHubDB_v11_WebStage2A02;"
        "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;"
    )
    try:
        c = conn.cursor()

        def q(sql: str, *params: object) -> pyodbc.Row | None:
            return c.execute(sql, *params).fetchone()

        order = q(
            "SELECT o.order_id,o.status,o.total_amount,o.total_tokens,u.username "
            "FROM dbo.Orders o JOIN dbo.Users u ON u.user_id=o.user_id WHERE o.order_id=?",
            int(manifest["order_id"]),
        )
        assert order and order[1] == "partially_refunded" and str(order[4]) == "web_customer", order
        order_id = int(order[0])
        summed = q(
            "SELECT COUNT(*),COALESCE(SUM(subtotal),0),COALESCE(SUM(total_tokens),0) "
            "FROM dbo.OrderDetails WHERE order_id=?",
            order_id,
        )
        assert summed[0] == 1 and summed[1] == order[2] and summed[2] == order[3], (summed, order)
        refund = q(
            "SELECT refund_amount,refundable_tokens,consumed_tokens,payout_state,external_payout_ref "
            "FROM dbo.RefundLedger WHERE order_id=?",
            order_id,
        )
        assert refund and str(refund[0]) == "7.58" and refund[1] == 85791 and refund[2] == 50000, (
            refund
        )
        assert refund[3] == "settled" and str(refund[4]).startswith("SIM-")
        assert refund[1] + refund[2] == order[3]
        used = q(
            "SELECT COUNT(*),COALESCE(SUM(l.tokens_used),0),MIN(l.account_id) "
            "FROM dbo.TokenUsageLogs l JOIN dbo.Users u ON u.user_id=l.user_id "
            "WHERE u.username='web_customer' AND l.product_id=?",
            int(manifest["product_id"]),
        )
        assert used[0] == 1 and used[1] == 50000 and used[2] is not None, used
        actual_usage_account = int(used[2])
        billed = q(
            "SELECT a.account_name,i.current_quota,"
            "(SELECT COALESCE(SUM(change_amount),0) FROM dbo.InventoryLog "
            " WHERE account_id=a.account_id) "
            "FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id "
            "WHERE a.account_id=?",
            actual_usage_account,
        )
        assert billed and billed[1] == 99950000 and billed[2] == billed[1], billed
        quota = q(
            "SELECT a.account_name,a.total_quota,i.current_quota "
            "FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id "
            "WHERE a.account_id=?",
            int(manifest["account_id"]),
        )
        assert quota and quota[0] == "Stage2上游账号A01", quota
        assert quota[2] == 1008000 and quota[1] == 1008000, quota
        logs = q(
            "SELECT COALESCE(SUM(change_amount),0),COUNT(*) "
            "FROM dbo.InventoryLog WHERE account_id=?",
            int(manifest["account_id"]),
        )
        assert logs[0] == quota[2], (logs, quota)
        task = q(
            "SELECT COUNT(*),COALESCE(SUM(actual_amount),0) "
            "FROM dbo.RestockTask WHERE account_id=? AND status='completed'",
            int(manifest["account_id"]),
        )
        assert task[0] == 1 and task[1] == 8000, task
        customer = q("SELECT COUNT(*) FROM dbo.Users WHERE username='stage2_new_A01'")
        assert customer[0] == 1
        bad_duplicate = q(
            "SELECT COUNT(*) FROM dbo.Users WHERE username='stage2_new_A01' "
            "OR email='stage2_other_A01@example.invalid'"
        )
        assert bad_duplicate[0] == 1
        balance = q(
            "SELECT COALESCE(SUM(remaining_tokens),0) "
            "FROM dbo.TokenBalances t JOIN dbo.Users u ON u.user_id=t.user_id "
            "WHERE u.username='web_customer' AND t.model_provider='Other'"
        )
        assert balance[0] == 0, balance
        schema = q(
            "SELECT (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0),"
            "(SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled=0 AND is_not_trusted=0)"
        )
        assert schema[0] == 18 and schema[1] == 22, schema
        events = manifest["events"]
        checks = {
            "customer_signup_unique": customer[0],
            "rejected_duplicate_never_created": bad_duplicate[0],
            "order_id": order_id,
            "order_status": order[1],
            "order_amount": str(order[2]),
            "order_tokens": int(order[3]),
            "order_item_count": int(summed[0]),
            "refund_amount": str(refund[0]),
            "refundable_tokens": int(refund[1]),
            "consumed_tokens": int(refund[2]),
            "refund_state": refund[3],
            "usage_count": int(used[0]),
            "usage_tokens": int(used[1]),
            "actual_usage_account_id": actual_usage_account,
            "actual_usage_account_name": str(billed[0]),
            "actual_usage_account_current_quota": int(billed[1]),
            "balance_after_refund": int(balance[0]),
            "upstream_account_id": int(manifest["account_id"]),
            "initial_account_quota": 1000000,
            "restock_actual": int(task[1]),
            "upstream_total_quota": int(quota[1]),
            "upstream_remaining_quota": int(quota[2]),
            "inventory_log_sum": int(logs[0]),
            "tables": int(schema[0]),
            "trusted_foreign_keys": int(schema[1]),
        }
        result = {
            "database": manifest["database"],
            "execution": "read-only DB queries, real SQL Server; not human review",
            "screenshot_count": len(screenshots),
            "screenshot_sha256_verified": True,
            "browser_event_count": len(events),
            "observations": checks,
            "result": "PASS",
            "limitations": [
                "Preview mode uses app_runtime_probe; real restricted Windows service account not verified.",
                "All payment/usage/refund settlement is locally simulated.",
                "Screenshots taken by Edge headless automation, not personally signed by a second team member.",
            ],
        }
        (directory / "database_reconciliation.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print("PASS screenshot SHA256", len(screenshots), "SQL reconciliations", len(checks))
        print(json.dumps(checks, ensure_ascii=False, indent=2))
    finally:
        conn.close()


if __name__ == "__main__":
    main()
