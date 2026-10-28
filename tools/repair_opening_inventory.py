"""Preview/apply the approved opening-stock repair; never infer arbitrary adjustments."""

from __future__ import annotations

import argparse
import json
import re
import uuid
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parents[1]
MARKER = "APP_INITIAL_QUOTA_V1"


def connect(server: str, database: str, *, autocommit: bool = False) -> pyodbc.Connection:
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};SERVER="
        + server
        + ";DATABASE="
        + database
        + ";Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;",
        autocommit=autocommit,
    )


def batches(source: str) -> list[str]:
    return [part.strip() for part in re.split(r"(?im)^GO\s*$", source) if part.strip()]


def procedure_source() -> str:
    source = (ROOT / "sql/app/install.sql").read_text(encoding="utf-8")
    match = re.search(r"(?m)^CREATE PROCEDURE app\.\[Execute\]\s*$", source)
    if match is None:
        raise ValueError("Application execution procedure missing from installation source")
    return batches(source[match.start() :])[0].replace(
        "CREATE PROCEDURE", "CREATE OR ALTER PROCEDURE", 1
    )


def planned_rows(db: pyodbc.Connection, manifest: dict[str, object]) -> list[tuple[int, int]]:
    approved = manifest["accounts"]
    if not isinstance(approved, list):
        raise ValueError("Invalid approved account manifest")
    if db.execute(
        "SELECT COUNT(*) FROM dbo.UpstreamAccount a FULL OUTER JOIN dbo.Inventory i "
        "ON i.account_id=a.account_id WHERE a.account_id IS NULL OR i.account_id IS NULL"
    ).fetchval():
        raise ValueError("Missing account/inventory pair")
    rows = db.execute("""
SELECT a.account_id,a.provider,a.account_name,a.total_quota-a.used_quota,
 COALESCE(SUM(CONVERT(bigint,l.change_amount)),0),i.current_quota,
 SUM(CASE WHEN l.reason=N'APP_INITIAL_QUOTA_V1' THEN 1 ELSE 0 END)
FROM dbo.UpstreamAccount a WITH(UPDLOCK,HOLDLOCK)
JOIN dbo.Inventory i WITH(UPDLOCK,HOLDLOCK) ON i.account_id=a.account_id
LEFT JOIN dbo.InventoryLog l WITH(UPDLOCK,HOLDLOCK) ON l.account_id=a.account_id
GROUP BY a.account_id,a.provider,a.account_name,a.total_quota,a.used_quota,i.current_quota
""").fetchall()
    pending = []
    for account_id, provider, name, quota, movements, inventory, markers in rows:
        if quota != inventory:
            raise ValueError(f"Account/inventory mismatch: {account_id}")
        delta = quota - movements
        if delta == 0:
            continue
        match = next(
            (
                item
                for item in approved
                if isinstance(item, dict) and item.get("account_id") == account_id
            ),
            None,
        )
        if (
            match is None
            or match.get("provider") != provider
            or match.get("account_name") != name
            or match.get("opening_amount") != delta
            or markers != 0
        ):
            raise ValueError(f"Unapproved inventory discrepancy: {account_id}")
        pending.append((int(account_id), int(delta)))
    return pending


def backup(server: str, database: str) -> str:
    with connect(server, "master", autocommit=True) as db:
        folder = db.execute(
            "SELECT CONVERT(nvarchar(4000),SERVERPROPERTY('InstanceDefaultBackupPath'))"
        ).fetchval()
        if not folder:
            raise RuntimeError("SQL Server backup directory unavailable")
        path = str(folder).rstrip("\\/") + "\\" + database + "_opening_" + uuid.uuid4().hex + ".bak"
        for statement in (
            f"BACKUP DATABASE [{database}] TO DISK=? WITH COPY_ONLY,CHECKSUM",
            "RESTORE VERIFYONLY FROM DISK=? WITH CHECKSUM",
        ):
            cursor = db.execute(statement, path)
            while cursor.nextset():
                pass
            cursor.close()
        return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", default=r"localhost\SQLEXPRESS")
    parser.add_argument("--database", required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"TokenHubDB_v11_Web[A-Za-z0-9_]+", args.database):
        raise ValueError("Only explicitly selected Web databases are supported")
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    if manifest.get("database") != args.database:
        raise ValueError("Manifest database does not match target")
    procedure = procedure_source()
    db = connect(args.server, args.database)
    try:
        if not db.execute("SELECT OBJECT_ID('app.Execute','P')").fetchval():
            raise ValueError("Installed application required")
        db.execute("SET XACT_ABORT ON; SET TRANSACTION ISOLATION LEVEL SERIALIZABLE")
        pending = planned_rows(db, manifest)
        db.rollback()
        print(json.dumps({"database": args.database, "pending": pending, "apply": args.apply}))
        if not args.apply:
            return
        print("Verified backup:", backup(args.server, args.database), flush=True)
        pending = planned_rows(db, manifest)
        for batch in batches((ROOT / "sql/app/opening_inventory.sql").read_text(encoding="utf-8")):
            db.execute(batch)
        db.execute(procedure)
        for account_id, amount in pending:
            db.execute(
                """
INSERT dbo.InventoryLog(account_id,change_type,change_amount,reference_type,reference_id,reason,created_at)
SELECT account_id,'purchase',?,'manual',NULL,?,created_at FROM dbo.UpstreamAccount WHERE account_id=?
""",
                amount,
                MARKER,
                account_id,
            )
        if planned_rows(db, manifest):
            raise RuntimeError("Opening reconciliation failed")
        db.commit()
        print("PASS opening inventory repaired; all inventory movements reconcile")
    except BaseException:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    main()
