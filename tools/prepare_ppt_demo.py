"""Prepare the stage-2 slide walkthrough before starting the Web server."""

from __future__ import annotations

import argparse
import getpass
import json
from datetime import datetime

import bcrypt
import pyodbc
from seed_dashboard_recent import ROOT, validate_database


def prepare(connection: pyodbc.Connection, password: str) -> dict[str, object]:
    """Prepare one atomic batch. The caller commits or rolls back all writes."""
    encoded = password.encode("utf-8")
    if not 12 <= len(encoded) <= 72:
        raise ValueError("Password must contain 12–72 UTF-8 bytes")
    hashed = bcrypt.hashpw(encoded, bcrypt.gensalt()).decode("ascii")
    cursor = connection.cursor()
    try:
        cursor.execute("SET XACT_ABORT ON; SET NOCOUNT ON; BEGIN TRANSACTION;")
        cursor.execute(
            "DECLARE @result INT; EXEC @result=sys.sp_getapplock "
            "@Resource=N'ppt.walkthrough.prepare',@LockMode='Exclusive',"
            "@LockOwner='Transaction',@LockTimeout=10000; "
            "IF @result<0 THROW 55820,'Another PPT preparation is running',1;"
        )
        cursor.execute(
            "SELECT password_hash FROM dbo.Users WITH(UPDLOCK,HOLDLOCK) WHERE username='chen_demo'"
        )
        existing = cursor.fetchone()
        if existing and not bcrypt.checkpw(encoded, existing[0].encode("ascii")):
            raise ValueError("chen_demo exists. Enter its original password or use a new batch")
        cursor.execute((ROOT / "sql/app/ppt_demo_data.sql").read_text(encoding="utf-8"), hashed)
        while cursor.description is None:
            if not cursor.nextset():
                raise RuntimeError("PPT preparation returned no result")
        return json.loads(cursor.fetchone()[0])
    finally:
        cursor.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True)
    parser.add_argument("--server", default=r"localhost\SQLEXPRESS")
    args = parser.parse_args()
    validate_database(args.database)
    password = getpass.getpass("Set chen_demo password (12–72 UTF-8 bytes): ")
    if password != getpass.getpass("Confirm chen_demo password: "):
        raise SystemExit("Passwords do not match")
    output = ROOT / "result/webapp" / args.database.removeprefix("TokenHubDB_v11_")
    output.mkdir(parents=True, exist_ok=True)
    evidence = output / ("ppt_baseline_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f") + ".json")
    connection = pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={args.server};DATABASE={args.database};"
        "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;",
        autocommit=False,
        timeout=10,
    )
    try:
        result = prepare(connection, password)
        connection.commit()
    except BaseException:
        connection.rollback()
        raise
    finally:
        connection.close()
    evidence.write_text(
        json.dumps({"database": args.database, **result}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print("PASS: chen_demo / 入门体验套餐 / 展示库存账号")
    print("Dashboard baseline:", evidence)


if __name__ == "__main__":
    main()
