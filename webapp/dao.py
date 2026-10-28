"""The only runtime module that opens SQL connections or executes SQL."""

from __future__ import annotations

import json
import re
from collections.abc import Iterator
from contextlib import contextmanager
from decimal import Decimal

import pyodbc
from flask import current_app, g

from .errors import AppError, database_error

JsonObject = dict[str, object]
# Preview impersonation must never survive an ODBC pooled connection reset.
pyodbc.pooling = False


def connect() -> pyodbc.Connection:
    config = current_app.config
    connection = pyodbc.connect(
        f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={config['DB_SERVER']};"
        f"DATABASE={config['DB_DATABASE']};Trusted_Connection=yes;"
        "Encrypt=yes;TrustServerCertificate=yes;",
        autocommit=False,
        timeout=5,
    )
    connection.timeout = 15
    if config.get("DB_PREVIEW"):
        connection.execute("EXECUTE AS USER=N'app_runtime_probe'")
    elif connection.execute("SELECT IS_SRVROLEMEMBER('sysadmin')").fetchval() == 1:
        connection.close()
        raise AppError("UNSAFE_DATABASE_IDENTITY", "请使用专用受限 Windows 账户启动服务", 503)
    return connection


@contextmanager
def unit_of_work() -> Iterator[pyodbc.Connection]:
    connection = None
    try:
        connection = connect()
        yield connection
        connection.commit()
    except (pyodbc.Error, OSError) as error:
        current_app.logger.error(
            "database_failure request_id=%s operation=%s role=%s sqlstate=%s native_codes=%s",
            getattr(g, "request_id", "setup"),
            getattr(g, "operation", "unknown"),
            getattr(g, "role", "guest"),
            str(error.args[0])[:5] if isinstance(error, pyodbc.Error) and error.args else "OS_IO",
            ",".join(re.findall(r"\((\d{3,5})\)", str(error))),
        )
        raise database_error(error) from None
    finally:
        if connection is not None:
            cleanup(connection)


def cleanup(connection: pyodbc.Connection) -> None:
    actions = [connection.rollback]
    if current_app.config.get("DB_PREVIEW"):
        actions.append(lambda: connection.execute("REVERT"))
    actions.append(connection.close)
    for action in actions:
        try:
            action()
        except (pyodbc.Error, OSError):
            current_app.logger.warning(
                "connection_cleanup_failed request_id=%s operation=%s",
                getattr(g, "request_id", "setup"),
                getattr(g, "operation", "unknown"),
            )


def rows(cursor: pyodbc.Cursor) -> list[JsonObject]:
    while cursor.description is None:
        if not cursor.nextset():
            return []
    names = [column[0] for column in cursor.description]
    return [dict(zip(names, row, strict=True)) for row in cursor.fetchall()]


PROCEDURES = {
    "lookup": "EXEC app.AuthLookup @kind=?, @account=?",
    "register": "EXEC app.RegisterCustomer @username=?, @email=?, @password_hash=?",
    "start": "EXEC app.StartSession @kind=?, @identity_id=?, @token_hash=?",
    "resolve": "EXEC app.ResolveSession @token_hash=?",
    "end": "EXEC app.EndSession @token_hash=?",
}


def authentication(name: str, *parameters: object) -> list[JsonObject]:
    with unit_of_work() as connection:
        return rows(connection.cursor().execute(PROCEDURES[name], *parameters))


def execute(token_hash: bytes | None, operation: str, payload: JsonObject) -> JsonObject:
    with unit_of_work() as connection:
        result = rows(
            connection.cursor().execute(
                "EXEC app.[Execute] @token_hash=?, @operation=?, @payload=?",
                token_hash,
                operation,
                json.dumps(payload, ensure_ascii=False),
            )
        )
        if not result or "data" not in result[0]:
            raise AppError("DATABASE_PROTOCOL", "系统暂时无法完成操作", 500)
        return wire_values(json.loads(str(result[0]["data"]), parse_float=Decimal))


def wire_values(value: object, key: str = "") -> object:
    if isinstance(value, dict):
        return {name: wire_values(item, name) for name, item in value.items()}
    if isinstance(value, list):
        return [wire_values(item) for item in value]
    if value is not None and (
        isinstance(value, Decimal)
        or "token" in key
        or "quota" in key
        or key
        in {
            "price",
            "unit_price",
            "subtotal",
            "total_amount",
            "refund_amount",
            "target_amount",
            "actual_amount",
            "safety_threshold",
        }
    ):
        return str(value)
    return value
