"""Reconcile legacy synthetic history with the project's fixed-seed generator.

Only applies to a separately backed-up, explicitly named v1.1 sandbox.
Never patches a v0.1/v1.0 original or claims to recover an unknown true event time.
"""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
from datetime import datetime
import json
from pathlib import Path
import re
import subprocess
import sys
from uuid import uuid4

import pyodbc

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools import datagen

USAGE_ID = ("user_id", "product_id", "tokens_used", "upstream_tokens_consumed", "api_endpoint")
ORDER_KEYS = ("order_id", "user_id", "status", "created_at", "paid_at")
DETAIL_KEYS = ("detail_id", "order_id", "product_id", "quantity", "unit_price",
               "subtotal", "tokens_per_unit", "total_tokens")
SUMMARY_KEYS = ("summary_id", "user_id", "product_id", "period_type", "period_start",
                "period_end", "total_tokens_used", "total_upstream_consumed",
                "request_count", "last_updated_at")


def conn(server: str, database: str, autocommit: bool = True) -> pyodbc.Connection:
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};SERVER=" + server
        + ";DATABASE=" + database + ";Trusted_Connection=yes;TrustServerCertificate=yes;",
        autocommit=autocommit,
    )


def rows(db: pyodbc.Connection, table: str, keys: tuple[str, ...]) -> list[dict]:
    assert re.fullmatch(r"[A-Za-z_]+", table)
    assert all(re.fullmatch(r"[A-Za-z_]+", k) for k in keys)
    sql = "SELECT " + ",".join("[" + x + "]" for x in keys) + " FROM dbo." + table
    return [dict(zip(keys, row)) for row in db.execute(sql)]


def require_same(actual: list[dict], expected: list[dict],
                 keys: tuple[str, ...], label: str) -> None:
    def normalized(input_rows):
        return Counter(tuple(row[x] for x in keys) for row in input_rows)
    if normalized(actual) != normalized(expected):
        raise RuntimeError("Refused: canonical source data differs: " + label)


def invalid_counts(db: pyodbc.Connection) -> tuple[int, int, int, int]:
    sql = (
        "SELECT COUNT_BIG(*) FROM dbo.Orders o JOIN dbo.Users u ON o.user_id=u.user_id WHERE o.created_at<u.created_at",
        "SELECT COUNT_BIG(*) FROM dbo.TokenUsageLogs l JOIN dbo.Users u ON l.user_id=u.user_id WHERE l.used_at<u.created_at",
        """SELECT COUNT_BIG(*) FROM dbo.TokenUsageLogs l
           JOIN dbo.UpstreamAccount a ON a.account_id=l.account_id
           JOIN dbo.Products p ON p.product_id=l.product_id
           WHERE l.used_at<a.created_at OR
                 (a.expires_at IS NOT NULL AND l.used_at>=a.expires_at)
                 OR a.provider<>p.model_provider""",
        """WITH e AS(
            SELECT o.user_id,p.model_provider,o.paid_at t,0 k,d.detail_id id,
                   CONVERT(BIGINT,d.total_tokens) amount FROM dbo.Orders o
            JOIN dbo.OrderDetails d ON d.order_id=o.order_id
            JOIN dbo.Products p ON p.product_id=d.product_id WHERE o.status='paid'
            UNION ALL
            SELECT l.user_id,p.model_provider,l.used_at,1,l.log_id,
                   -CONVERT(BIGINT,l.tokens_used)
            FROM dbo.TokenUsageLogs l JOIN dbo.Products p ON p.product_id=l.product_id
           ), b AS(
            SELECT SUM(amount) OVER(PARTITION BY user_id,model_provider
                 ORDER BY t,k,id ROWS UNBOUNDED PRECEDING) running_balance FROM e
           ) SELECT COUNT_BIG(*) FROM b WHERE running_balance<0""",
    )
    return tuple(int(db.execute(s).fetchval()) for s in sql)


def verify_ledger(db: pyodbc.Connection) -> None:
    queries = (
        """SELECT COUNT(*) FROM dbo.UpstreamAccount a JOIN dbo.Inventory i
           ON i.account_id=a.account_id WHERE i.current_quota<>a.total_quota-a.used_quota""",
        """SELECT COUNT(*) FROM dbo.UpstreamAccount a OUTER APPLY(
          SELECT SUM(CONVERT(BIGINT,t.upstream_tokens_consumed)) n
          FROM dbo.TokenUsageLogs t WHERE t.account_id=a.account_id) x
          WHERE a.used_quota<>COALESCE(x.n,0)""",
        """SELECT COUNT(*) FROM dbo.Inventory i OUTER APPLY(
          SELECT SUM(l.change_amount) n FROM dbo.InventoryLog l WHERE l.account_id=i.account_id) x
          WHERE i.current_quota<>COALESCE(x.n,0)""",
        """SELECT COUNT(*) FROM dbo.InventoryLog l LEFT JOIN dbo.TokenUsageLogs t
             ON t.log_id=l.reference_id WHERE l.reference_type='manual'
           AND l.reference_id IS NOT NULL
           AND (t.log_id IS NULL OR t.account_id<>l.account_id
                OR l.created_at<>t.used_at
                OR l.change_amount<>-CONVERT(BIGINT,t.upstream_tokens_consumed))""",
    )
    if any(db.execute(sql).fetchval() != 0 for sql in queries):
        raise RuntimeError("Historical balances/quota/movement ledger do not reconcile")


def plan(db: pyodbc.Connection) -> dict:
    if db.execute("SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0").fetchval() != 15:
        raise RuntimeError("Expected isolated 15-table v1.1")
    if db.execute("SELECT COUNT(*) FROM sys.triggers WHERE name LIKE 'trg_W5_%' AND is_disabled=0").fetchval() != 13:
        raise RuntimeError("Required 13 v1.1 triggers not present")
    require_same(rows(db, "Orders", ORDER_KEYS), datagen.orders, ORDER_KEYS, "Orders")
    require_same(rows(db, "OrderDetails", DETAIL_KEYS), datagen.order_details, DETAIL_KEYS, "OrderDetails")
    require_same(rows(db, "UsageSummary", SUMMARY_KEYS), datagen.usage_summary, SUMMARY_KEYS, "UsageSummary")
    require_same(rows(db, "TokenBalances", ("balance_id", "user_id", "model_provider", "remaining_tokens")),
                 datagen.token_balances,
                 ("balance_id", "user_id", "model_provider", "remaining_tokens"), "TokenBalances")
    require_same(rows(db, "Inventory", ("inventory_id", "account_id", "current_quota")),
                 datagen.inventory, ("inventory_id", "account_id", "current_quota"), "Inventory")
    original = rows(db, "TokenUsageLogs", ("log_id", *USAGE_ID, "account_id", "used_at"))
    require_same(original, datagen.usage_logs, USAGE_ID, "3000 usage facts")
    if len(original) != 3000:
        raise RuntimeError("Incorrect source usage row count")

    old_by_time, new_by_time = defaultdict(list), defaultdict(list)
    for x in original:
        old_by_time[(tuple(x[k] for k in USAGE_ID), x["used_at"])].append(x)
    for x in datagen.usage_logs:
        new_by_time[(tuple(x[k] for k in USAGE_ID), x["used_at"])].append(x)
    matched = []
    orphan_old, orphan_new = defaultdict(list), defaultdict(list)
    for key in set(old_by_time) | set(new_by_time):
        old = sorted(old_by_time[key], key=lambda x: x["log_id"])
        new = sorted(new_by_time[key], key=lambda x: x["log_id"])
        count = min(len(old), len(new))
        matched.extend(zip(old[:count], new[:count]))
        orphan_old[key[0]].extend(old[count:])
        orphan_new[key[0]].extend(new[count:])
    remaining_old = {k: v for k, v in orphan_old.items() if v}
    remaining_new = {k: v for k, v in orphan_new.items() if v}
    if set(remaining_old) != set(remaining_new) or sum(map(len, remaining_old.values())) != 1:
        raise RuntimeError("Cannot uniquely identify corrected usage timestamp")
    for key in remaining_old:
        if len(remaining_old[key]) != len(remaining_new[key]) or len(remaining_old[key]) != 1:
            raise RuntimeError("Ambiguous canonical usage match")
        matched.append((remaining_old[key][0], remaining_new[key][0]))
    if len(matched) != 3000 or len({o["log_id"] for o, _ in matched}) != 3000:
        raise RuntimeError("Canonical event pairing is incomplete")

    update_usage = [
        {"log_id": o["log_id"], "from_account": o["account_id"], "to_account": n["account_id"],
         "from_time": o["used_at"], "to_time": n["used_at"]}
        for o, n in matched if (o["account_id"], o["used_at"]) != (n["account_id"], n["used_at"])
    ]
    if (sum(x["from_account"] != x["to_account"] for x in update_usage),
        sum(x["from_time"] != x["to_time"] for x in update_usage)) != (225, 1):
        raise RuntimeError("Unexpected historical event changes")

    users = rows(db, "Users", ("user_id", "username", "status", "created_at", "updated_at"))
    require_same(users, datagen.users, ("user_id", "username", "status", "updated_at"), "Users")
    canonical_users = {x["user_id"]: x for x in datagen.users}
    update_users = [
        {"user_id": u["user_id"], "from_time": u["created_at"],
         "to_time": canonical_users[u["user_id"]]["created_at"]}
        for u in users if u["created_at"] != canonical_users[u["user_id"]]["created_at"]
    ]
    if len(update_users) != 11:
        raise RuntimeError("Unexpected user date corrections")
    accounts = rows(db, "UpstreamAccount", ("account_id", "provider", "total_quota", "used_quota"))
    require_same(accounts, datagen.accounts, ("account_id", "provider"), "Accounts")
    ca = {x["account_id"]: x for x in datagen.accounts}
    update_accounts = [
        {"account_id": x["account_id"], "from_total": x["total_quota"],
         "from_used": x["used_quota"], "to_total": ca[x["account_id"]]["total_quota"],
         "to_used": ca[x["account_id"]]["used_quota"]}
        for x in accounts if (x["total_quota"], x["used_quota"]) !=
        (ca[x["account_id"]]["total_quota"], ca[x["account_id"]]["used_quota"])
    ]
    if {x["account_id"] for x in update_accounts} != {7, 8}:
        raise RuntimeError("Unexpected account quota corrections")
    if any(x["from_total"]-x["from_used"] != x["to_total"]-x["to_used"]
           for x in update_accounts):
        raise RuntimeError("Inventory reserve would change")

    ledger = rows(db, "InventoryLog", ("log_id", "account_id", "change_type",
                                     "change_amount", "reference_type", "reference_id", "created_at"))
    ref_by_event = {x["reference_id"]: x for x in ledger
                    if x["reference_type"] == "manual" and x["reference_id"] is not None}
    if len(ref_by_event) != 3000:
        raise RuntimeError("Opaque legacy references are not uniquely identified")
    for usage in original:
        entry = ref_by_event.get(usage["log_id"])
        if not entry or (entry["account_id"], entry["created_at"], entry["change_amount"],
                         entry["change_type"]) != (
            usage["account_id"], usage["used_at"], -usage["upstream_tokens_consumed"],
            "consumption",
        ):
            raise RuntimeError("Opaque usage reference cannot be verified by time, ID, amount and account")
    init = [x for x in ledger if x["change_type"] == "purchase"
            and x["reference_type"] is None and x["reference_id"] is None]
    if len(init) != 8 or len({x["account_id"] for x in init}) != 8:
        raise RuntimeError("Expected one initial purchase per account")
    canonical_initial = {x["account_id"]: x["change_amount"] for x in datagen.inventory_logs
                         if x["change_type"] == "purchase"}
    update_opening = [
        {"log_id": x["log_id"], "account_id": x["account_id"],
         "from_amount": x["change_amount"], "to_amount": canonical_initial[x["account_id"]]}
        for x in init if x["change_amount"] != canonical_initial[x["account_id"]]
    ]
    if {x["account_id"] for x in update_opening} != {7, 8}:
        raise RuntimeError("Unexpected opening purchase corrections")

    excepts = rows(db, "ExceptionLog", ("exception_id", "exception_type",
                                       "related_table", "related_id"))
    require_same(excepts, datagen.exception_logs,
                 ("exception_id", "exception_type", "related_table"), "ExceptionLog")
    original_ids = {x["exception_id"]: x["related_id"] for x in datagen.exception_logs}
    update_exceptions = [
        {"exception_id": x["exception_id"], "from_id": x["related_id"],
         "to_id": original_ids[x["exception_id"]]}
        for x in excepts if x["related_id"] != original_ids[x["exception_id"]]
    ]
    if [x["exception_id"] for x in update_exceptions] != [2]:
        raise RuntimeError("Unexpected exception references")
    return {
        "users": sorted(update_users, key=lambda x: x["user_id"]),
        "usage": sorted(update_usage, key=lambda x: x["log_id"]),
        "accounts": sorted(update_accounts, key=lambda x: x["account_id"]),
        "opening": sorted(update_opening, key=lambda x: x["account_id"]),
        "exceptions": update_exceptions,
    }


def execute_update(db: pyodbc.Connection, sql: str, *params) -> None:
    cur = db.execute(sql, *params)
    if cur.rowcount != 1:
        raise RuntimeError("Historical record changed, update aborted")


def reconcile(db: pyodbc.Connection, p: dict) -> None:
    for x in p["users"]:
        execute_update(db, "UPDATE dbo.Users SET created_at=? WHERE user_id=? AND created_at=?",
                       x["to_time"], x["user_id"], x["from_time"])
    for x in p["usage"]:
        execute_update(db, "UPDATE dbo.TokenUsageLogs SET account_id=?,used_at=? "
                       "WHERE log_id=? AND account_id=? AND used_at=?",
                       x["to_account"], x["to_time"], x["log_id"],
                       x["from_account"], x["from_time"])
        execute_update(db, "UPDATE dbo.InventoryLog SET account_id=?,created_at=? "
                       "WHERE reference_type='manual' AND reference_id=? "
                       "AND account_id=? AND created_at=?",
                       x["to_account"], x["to_time"], x["log_id"],
                       x["from_account"], x["from_time"])
    for x in p["accounts"]:
        execute_update(db, "UPDATE dbo.UpstreamAccount SET total_quota=?,used_quota=? "
                       "WHERE account_id=? AND total_quota=? AND used_quota=?",
                       x["to_total"], x["to_used"], x["account_id"],
                       x["from_total"], x["from_used"])
    for x in p["opening"]:
        execute_update(db, "UPDATE dbo.InventoryLog SET change_amount=? "
                       "WHERE log_id=? AND account_id=? AND change_amount=?",
                       x["to_amount"], x["log_id"], x["account_id"], x["from_amount"])
    for x in p["exceptions"]:
        execute_update(db, "UPDATE dbo.ExceptionLog SET related_id=? "
                       "WHERE exception_id=? AND related_table='Inventory' AND related_id=?",
                       x["to_id"], x["exception_id"], x["from_id"])
    if invalid_counts(db) != (0, 0, 0, 0):
        raise RuntimeError("Repaired timeline or account validity still fails")
    verify_ledger(db)


def backup(server: str, dbname: str) -> str:
    master = conn(server, "master")
    backupdir = master.execute(
        "SELECT CONVERT(nvarchar(400),SERVERPROPERTY('InstanceDefaultBackupPath'))"
    ).fetchval()
    if not backupdir:
        raise RuntimeError("Default SQL Server backup directory unavailable")
    filename = str(Path(backupdir) / (dbname + "_PreReconcile_" + uuid4().hex[:12] + ".bak"))
    for sql in (
        "BACKUP DATABASE [" + dbname + "] TO DISK=N'" + filename.replace("'", "''")
        + "' WITH COPY_ONLY,CHECKSUM",
        "RESTORE VERIFYONLY FROM DISK=N'" + filename.replace("'", "''") + "' WITH CHECKSUM",
    ):
        result = subprocess.run(["sqlcmd", "-S", server, "-d", "master",
                                 "-E", "-C", "-b", "-Q", sql],
                                capture_output=True, text=True, encoding="utf-8", errors="replace")
        if result.returncode:
            raise RuntimeError("Backup or restore-verification failed: "
                               + result.stdout[-400:] + result.stderr[-400:])
    return filename


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default=r"localhost\SQLEXPRESS")
    ap.add_argument("--database", required=True)
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--audit", type=Path)
    args = ap.parse_args()
    if not re.fullmatch(r"TokenHubDB_v11_[A-Za-z0-9_]+", args.database):
        raise SystemExit("Only independent v1.1 sandboxes may be repaired")
    if args.apply and not args.audit:
        raise SystemExit("--apply requires --audit to record the entire correction")
    if args.audit and args.audit.exists():
        raise RuntimeError("Existing audit file will not be overwritten")
    db = conn(args.server, args.database)
    before = invalid_counts(db)
    if before != (20, 402, 225, 1):
        raise RuntimeError("Unknown historical anomaly profile; refuse generated-data repair")
    verify_ledger(db)
    p = plan(db)
    print("PASS deterministic dataset fingerprints match (no secrets queried)")
    print("BEFORE:", before, "PLAN:", {k: len(v) for k, v in p.items()})
    if not args.apply:
        print("DRY RUN; no database writes")
        return
    file = backup(args.server, args.database)
    print("PASS SQL Server COPY_ONLY / CHECKSUM / VERIFYONLY before remediation")
    db.close()
    db = conn(args.server, args.database, autocommit=False)
    try:
        if plan(db) != p:
            raise RuntimeError("Data changed after backup; refuse repair")
        reconcile(db, p)
        db.commit()
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()
    db = conn(args.server, args.database)
    after = invalid_counts(db)
    verify_ledger(db)
    if after != (0, 0, 0, 0):
        raise RuntimeError("Post-commit invariant failure: restore from backup")
    def convert(item):
        return {k: (v.isoformat() if isinstance(v, datetime) else v)
                for k, v in item.items()}
    manifest = {
        "dataset": "fixed-seed synthetic sample from tools/datagen.py",
        "database": args.database, "before": before, "after": after,
        "backup": file, "changes": {k: [convert(v) for v in rows] for k, rows in p.items()},
        "note": "Synthetic reconstruction, not an assertion of real-world occurrence times. v0.1 unchanged.",
    }
    assert args.audit is not None
    args.audit.parent.mkdir(parents=True, exist_ok=True)
    args.audit.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                          encoding="utf-8")
    print("AFTER:", after, "AUDIT:", args.audit)
    print("PASS synthetic history reconciled, account quota and inventory ledger balanced")


if __name__ == "__main__":
    main()
