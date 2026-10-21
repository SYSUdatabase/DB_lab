"""Run under the final Windows account to verify its actual SQL permissions."""

from __future__ import annotations

import json
import os

import pyodbc


def main() -> None:
    database = os.environ["DB_LAB_APP_DATABASE"]
    server = os.environ.get("DB_LAB_SERVER", r"localhost\SQLEXPRESS")
    db = pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};SERVER="
        + server
        + ";DATABASE="
        + database
        + ";Trusted_Connection=yes;TrustServerCertificate=yes;",
        autocommit=False,
    )
    try:
        row = db.execute(
            "SELECT ORIGINAL_LOGIN(),IS_SRVROLEMEMBER('sysadmin'),IS_MEMBER('db_owner')"
        ).fetchone()
        if row[1] != 0 or row[2] != 0:
            raise RuntimeError("Runtime must not be sysadmin/db_owner")
        denied = []
        for statement in (
            "SELECT TOP(0) * FROM dbo.Users",
            "UPDATE dbo.Products SET price=price",
            "CREATE TABLE app.PermissionEscape(id int)",
        ):
            try:
                db.execute(statement)
            except pyodbc.Error as error:
                if "229" not in str(error) and "262" not in str(error):
                    raise
                denied.append(True)
            else:
                raise RuntimeError("Unexpected runtime permission")
        cursor = db.execute("EXEC app.[Execute] @operation='products.list'")
        while cursor.description is None:
            if not cursor.nextset():
                raise RuntimeError("No catalog response")
        if not json.loads(cursor.fetchone()[0])["items"]:
            raise RuntimeError("Catalog unexpectedly empty")
        print(
            json.dumps(
                {
                    "login": row[0],
                    "sysadmin": row[1],
                    "db_owner": row[2],
                    "denied_checks": len(denied),
                    "catalog": "PASS",
                }
            )
        )
    finally:
        db.close()


if __name__ == "__main__":
    main()
