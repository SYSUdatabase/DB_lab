"""Authentication, role policy and input rules, independent of Flask routes."""

from __future__ import annotations

import hashlib
import secrets
from decimal import Decimal, InvalidOperation

import bcrypt

from . import dao
from .errors import AppError

JsonObject = dict[str, object]
INTEGER_FIELDS = {
    "product_id",
    "order_id",
    "detail_id",
    "account_id",
    "task_id",
    "quantity",
    "token_amount",
    "required_upstream_tokens",
    "tokens_used",
    "total_quota",
    "safety_threshold",
    "planned_amount",
    "actual_amount",
    "page",
}
ALLOWED = {
    "products.list": {"guest", "customer", "staff", "admin"},
    "products.save": {"admin"},
    "products.delete": {"admin"},
    "orders.list": {"customer", "staff", "admin"},
    "orders.get": {"customer", "staff", "admin"},
    "orders.create": {"customer"},
    "orders.item_add": {"customer"},
    "orders.item_set": {"customer"},
    "orders.item_delete": {"customer"},
    "orders.pay": {"customer"},
    "orders.cancel": {"customer", "staff", "admin"},
    "orders.delete": {"admin"},
    "usage.list": {"customer", "staff", "admin"},
    "usage.create": {"customer"},
    "balances.list": {"customer", "staff", "admin"},
    "inventory.list": {"staff", "admin"},
    "accounts.save": {"admin"},
    "accounts.delete": {"admin"},
    "restocks.list": {"staff", "admin"},
    "restocks.create": {"staff", "admin"},
    "restocks.complete": {"staff", "admin"},
    "refunds.list": {"customer", "staff", "admin"},
    "refunds.request": {"customer"},
    "refunds.settle": {"admin"},
}


def digest(token: str) -> bytes:
    return hashlib.sha256(token.encode("ascii")).digest()


def identity(token: str | None) -> JsonObject:
    if not token:
        return {"role": "guest"}
    try:
        hashed = digest(token)
    except (UnicodeError, ValueError):
        raise AppError("UNAUTHENTICATED", "请重新登录", 401) from None
    records = dao.authentication("resolve", hashed)
    if not records:
        raise AppError("UNAUTHENTICATED", "登录已失效，请重新登录", 401)
    return records[0]


def login(payload: JsonObject) -> tuple[str, JsonObject]:
    kind, account, password = (payload.get(key) for key in ("kind", "account", "password"))
    if (
        not isinstance(kind, str)
        or kind not in {"customer", "employee"}
        or not isinstance(account, str)
    ):
        raise AppError("INVALID_INPUT", "请选择登录入口并填写账号和密码", 400)
    if not account or len(account) > 50 or not isinstance(password, str):
        raise AppError("INVALID_INPUT", "请检查账号与密码格式", 400)
    if not 1 <= len(password.encode("utf-8")) <= 72:
        raise AppError("INVALID_INPUT", "密码长度不符合要求", 400)
    records = dao.authentication("lookup", kind, account)
    valid = False
    if records:
        try:
            valid = bcrypt.checkpw(password.encode(), str(records[0]["password_hash"]).encode())
        except ValueError:
            valid = False
    if not valid:
        raise AppError("LOGIN_FAILED", "账号或密码不正确", 401)
    token = secrets.token_urlsafe(32)
    principal = dao.authentication("start", kind, records[0]["identity_id"], digest(token))
    return token, principal[0]


def validate(payload: JsonObject) -> JsonObject:
    if any(
        key in payload
        for key in (
            "user_id",
            "employee_id",
            "role",
            "token_hash",
            "confirmed_employee_id",
            "upstream_tokens_used",
        )
    ):
        raise AppError("INVALID_INPUT", "请求包含不允许指定的身份或扣减字段", 400)
    for key, value in payload.items():
        if key in INTEGER_FIELDS and value is not None:
            if isinstance(value, bool) or not str(value).isascii() or not str(value).isdigit():
                raise AppError("INVALID_INPUT", "数量与编号必须为非负整数", 400)
            maximum = (
                9223372036854775807
                if key in {"total_quota", "safety_threshold", "planned_amount", "actual_amount"}
                else 2147483647
            )
            if int(str(value)) > maximum or (int(str(value)) == 0 and key != "safety_threshold"):
                raise AppError("INVALID_INPUT", "数值超出允许范围", 400)
        if isinstance(value, str) and len(value) > (4000 if key == "description" else 120):
            raise AppError("INVALID_INPUT", "输入内容过长", 400)
    if "price" in payload:
        try:
            price = Decimal(str(payload["price"]))
            if not price.is_finite() or price <= 0 or price > Decimal("99999999.99"):
                raise ValueError
            if price != price.quantize(Decimal("0.01")):
                raise ValueError
        except (ValueError, InvalidOperation):
            raise AppError("INVALID_INPUT", "价格须为大于零且最多两位小数的金额", 400) from None
    if "items" in payload:
        items = payload["items"]
        if not isinstance(items, list) or not 1 <= len(items) <= 50:
            raise AppError("INVALID_INPUT", "订单需要 1 至 50 项商品", 400)
        for item in items:
            if not isinstance(item, dict) or set(item) != {"product_id", "quantity"}:
                raise AppError("INVALID_INPUT", "请检查订单明细", 400)
            validate(item)
    return payload


def perform(operation: str, payload: JsonObject, token: str | None) -> JsonObject:
    principal = identity(token)
    role = str(principal["role"])
    if role not in ALLOWED[operation]:
        if role == "guest":
            raise AppError("UNAUTHENTICATED", "请先登录", 401)
        raise AppError("FORBIDDEN", "当前身份没有此操作权限", 403)
    validated = validate(payload)
    hashed = digest(token) if token else None
    if role == "customer" and "order_id" in validated:
        order = dao.execute(hashed, "orders.get", {"order_id": validated["order_id"]})
        if str(order["order"]["user_id"]) != str(principal["user_id"]):
            raise AppError("FORBIDDEN", "不可操作其他顾客的订单", 403)
    return dao.execute(hashed, operation, validated)
