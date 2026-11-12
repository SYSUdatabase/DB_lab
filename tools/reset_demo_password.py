"""Reset one built-in account in the isolated local demonstration database.

The new password is prompted without echoing and is never written to the log.
Never use this script with acceptance/evidence databases.
"""

from __future__ import annotations

import argparse
import getpass

import bcrypt
import pyodbc

DATABASE = "TokenHubDB_v11_WebManualA01"
SERVER = r"localhost\SQLEXPRESS"
ACCOUNTS = {
    "web_admin": ("dbo.Employees", "account", "employee_id"),
    "web_staff": ("dbo.Employees", "account", "employee_id"),
    "web_customer": ("dbo.Users", "username", "user_id"),
    "web_other": ("dbo.Users", "username", "user_id"),
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Reset one local TokenHub demonstration password")
    parser.add_argument(
        "--account",
        choices=sorted(ACCOUNTS),
        default="web_admin",
        help="Built-in demo account, default: web_admin",
    )
    args = parser.parse_args()

    password = getpass.getpass(f"New password for {args.account} (12-72 UTF-8 bytes): ")
    if not 12 <= len(password.encode("utf-8")) <= 72:
        raise SystemExit("Password must be 12-72 UTF-8 bytes; nothing was changed")
    if password != getpass.getpass("Confirm new password: "):
        raise SystemExit("Passwords do not match; nothing was changed")

    password_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("ascii")
    del password

    table, account_column, id_column = ACCOUNTS[args.account]
    conn = pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={SERVER};DATABASE={DATABASE};"
        "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;",
        autocommit=False,
        timeout=5,
    )
    try:
        cursor = conn.cursor()
        cursor.execute("SET XACT_ABORT ON;")
        actual_db = cursor.execute("SELECT DB_NAME()").fetchval()
        if actual_db != DATABASE:
            raise RuntimeError("Unexpected connected database; refusing to change password")

        cursor.execute(
            f"UPDATE {table} SET password_hash=? WHERE {account_column}=?",
            password_hash,
            args.account,
        )
        if cursor.rowcount != 1:
            raise RuntimeError("Expected exactly one matching demonstration account")

        session_column = "employee_id" if table == "dbo.Employees" else "user_id"
        cursor.execute(
            f"UPDATE app.Sessions SET revoked_at=SYSDATETIME() "
            f"WHERE {session_column}=(SELECT {id_column} FROM {table} "
            f"WHERE {account_column}=?) AND revoked_at IS NULL",
            args.account,
        )
        conn.commit()
        print(f"PASS password updated: {args.account}; existing sessions revoked")
        print("All business orders, balances, inventory and logs are unchanged.")
    except BaseException:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
