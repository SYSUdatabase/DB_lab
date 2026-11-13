"""Add repeatable recent samples before starting the stage-2 dashboard."""

from __future__ import annotations

import argparse
import json
import re
import secrets
from pathlib import Path

import bcrypt
import pyodbc

ROOT = Path(__file__).resolve().parents[1]
SAMPLE_USER = "dashboard_recent_sample"


def validate_database(database: str) -> None:
    if not re.fullmatch(r"TokenHubDB_v11_Web[A-Za-z0-9]{3,12}", database):
        raise ValueError("Recent samples require a v11 Web database")


def seed(connection: pyodbc.Connection) -> dict[str, object]:
    """Leave commit to the caller so all sample writes form one unit of work."""
    hashed = bcrypt.hashpw(secrets.token_bytes(32), bcrypt.gensalt()).decode("ascii")
    cursor = connection.cursor().execute(
        (ROOT / "sql/app/dashboard_recent_data.sql").read_text(encoding="utf-8"), hashed
    )
    try:
        while cursor.description is None:
            if not cursor.nextset():
                raise RuntimeError("Recent sample operation returned no result")
        return json.loads(cursor.fetchone()[0])
    finally:
        cursor.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True)
    parser.add_argument("--server", default=r"localhost\SQLEXPRESS")
    args = parser.parse_args()
    validate_database(args.database)
    connection = pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={args.server};DATABASE={args.database};"
        "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;",
        autocommit=False,
        timeout=10,
    )
    try:
        result = seed(connection)
        connection.commit()
        print(json.dumps({"database": args.database, **result}, ensure_ascii=False, indent=2))
    except BaseException:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == "__main__":
    main()
