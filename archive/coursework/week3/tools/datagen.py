from __future__ import annotations

import math
import random
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Any, Iterable

SEED = 20260923
rng = random.Random(SEED)
START = datetime(2026, 7, 1, 0, 0, 0)
END = datetime(2026, 9, 22, 23, 59, 59)
OUT_PATH = Path(__file__).resolve().parents[1] / "sql" / "02_insert_data.sql"


@dataclass(frozen=True)
class ProductSpec:
    product_id: int
    name: str
    price: Decimal
    provider: str
    token_amount: int
    required_upstream_tokens: int
    status: str = "active"


PRODUCTS = [
    ProductSpec(1, "OpenAI 50K Token包", Decimal("3.90"), "OpenAI", 50_000, 60_000),
    ProductSpec(2, "OpenAI 100K Token包", Decimal("6.90"), "OpenAI", 100_000, 120_000),
    ProductSpec(3, "OpenAI 500K Token包", Decimal("31.90"), "OpenAI", 500_000, 600_000),
    ProductSpec(4, "OpenAI 1M Token包", Decimal("59.90"), "OpenAI", 1_000_000, 1_200_000),
    ProductSpec(5, "Claude 100K Token包", Decimal("6.90"), "Claude", 100_000, 120_000),
    ProductSpec(6, "Claude 500K Token包", Decimal("31.90"), "Claude", 500_000, 600_000),
    ProductSpec(7, "Claude 1M Token包", Decimal("59.90"), "Claude", 1_000_000, 1_200_000),
    ProductSpec(8, "Gemini 100K Token包", Decimal("1.90"), "Gemini", 100_000, 120_000),
    ProductSpec(9, "Gemini 500K Token包", Decimal("7.90"), "Gemini", 500_000, 600_000),
    ProductSpec(10, "Gemini 1M Token包", Decimal("14.90"), "Gemini", 1_000_000, 1_200_000),
]
PRODUCT_BY_ID = {p.product_id: p for p in PRODUCTS}

ACCOUNT_SPECS = [
    (1, "OpenAI", "OpenAI-池-01", "active"),
    (2, "OpenAI", "OpenAI-池-02", "active"),
    (3, "OpenAI", "OpenAI-池-03", "active"),
    (4, "Claude", "Claude-池-01", "active"),
    (5, "Claude", "Claude-池-02", "active"),
    (6, "Claude", "Claude-池-03", "suspended"),
    (7, "Gemini", "Gemini-池-01", "expired"),
    (8, "Gemini", "Gemini-池-02", "depleted"),
]
ACCOUNTS_BY_PROVIDER: dict[str, list[int]] = defaultdict(list)
for account_id, provider, _, _ in ACCOUNT_SPECS:
    ACCOUNTS_BY_PROVIDER[provider].append(account_id)


def bcrypt_placeholder(prefix: str, number: int) -> str:
    body = f"{prefix}{number:02d}".ljust(53, "x")[:53]
    value = "$2b$12$" + body
    assert len(value) == 60
    return value


def random_datetime(start: datetime, end: datetime) -> datetime:
    seconds = int((end - start).total_seconds())
    return start + timedelta(seconds=rng.randint(0, seconds))


def order_datetime() -> datetime:
    while True:
        day = START.date() + timedelta(days=rng.randint(0, (END.date() - START.date()).days))
        if day.weekday() >= 5 and rng.random() < 0.55:
            continue
        hour = rng.choices(
            [9, 10, 11, 14, 15, 16, 17, 20, 21, 22],
            weights=[8, 10, 8, 8, 10, 10, 8, 7, 7, 5],
            k=1,
        )[0]
        return datetime.combine(day, datetime.min.time()).replace(
            hour=hour,
            minute=rng.randint(0, 59),
            second=rng.randint(0, 59),
        )


roles = [
    {
        "role_id": 1,
        "role_name": "admin",
        "description": "系统管理员，拥有全部应用层管理权限",
        "permissions": '{"all": true}',
    },
    {
        "role_id": 2,
        "role_name": "staff",
        "description": "客服与运营人员",
        "permissions": '{"orders":"read/write","users":"read","inventory":"read"}',
    },
    {
        "role_id": 3,
        "role_name": "customer",
        "description": "普通用户",
        "permissions": '{"products":"read","orders":"create","balance":"read"}',
    },
]

users: list[dict[str, Any]] = []
for user_id in range(1, 41):
    status = "active" if user_id <= 35 else ("frozen" if user_id <= 39 else "deleted")
    created_at = random_datetime(datetime(2026, 5, 1), datetime(2026, 8, 31))
    users.append(
        {
            "user_id": user_id,
            "username": f"user{user_id:03d}",
            "password_hash": bcrypt_placeholder("u", user_id),
            "email": f"user{user_id:03d}@example.edu",
            "phone": None if user_id % 7 == 0 else f"138{user_id:08d}",
            "status": status,
            "created_at": created_at,
            "updated_at": created_at + timedelta(days=rng.randint(0, 20)),
        }
    )

products = [
    {
        "product_id": p.product_id,
        "name": p.name,
        "description": f"{p.provider} API Token 虚拟套餐；教学用合成商品。",
        "price": p.price,
        "model_provider": p.provider,
        "token_amount": p.token_amount,
        "required_upstream_tokens": p.required_upstream_tokens,
        "status": p.status,
        "created_at": datetime(2026, 6, 20, 9, 0, 0),
    }
    for p in PRODUCTS
]

employees = [
    {
        "employee_id": 1,
        "name": "张经理",
        "role_id": 1,
        "account": "admin_zhang",
        "password_hash": bcrypt_placeholder("e", 1),
        "hire_date": date(2026, 1, 5),
        "status": "active",
    },
    {
        "employee_id": 2,
        "name": "李客服",
        "role_id": 2,
        "account": "staff_li",
        "password_hash": bcrypt_placeholder("e", 2),
        "hire_date": date(2026, 3, 15),
        "status": "active",
    },
    {
        "employee_id": 3,
        "name": "王运营",
        "role_id": 2,
        "account": "staff_wang",
        "password_hash": bcrypt_placeholder("e", 3),
        "hire_date": date(2026, 4, 20),
        "status": "active",
    },
    {
        "employee_id": 4,
        "name": "赵客服",
        "role_id": 2,
        "account": "staff_zhao",
        "password_hash": bcrypt_placeholder("e", 4),
        "hire_date": date(2026, 5, 12),
        "status": "active",
    },
    {
        "employee_id": 5,
        "name": "钱运营",
        "role_id": 2,
        "account": "staff_qian",
        "password_hash": bcrypt_placeholder("e", 5),
        "hire_date": date(2026, 6, 8),
        "status": "active",
    },
    {
        "employee_id": 6,
        "name": "孙客服",
        "role_id": 2,
        "account": "staff_sun",
        "password_hash": bcrypt_placeholder("e", 6),
        "hire_date": date(2026, 6, 25),
        "status": "inactive",
    },
]

status_values = ["paid"] * 85 + ["pending"] * 8 + ["cancelled"] * 5 + ["refunded"] * 2
rng.shuffle(status_values)
order_times = sorted(order_datetime() for _ in range(100))
user_ids = list(range(1, 36))
user_weights = [1.0 / (uid ** 0.55) for uid in user_ids]

orders: list[dict[str, Any]] = []
order_details: list[dict[str, Any]] = []
credits: dict[tuple[int, str], int] = defaultdict(int)
first_purchase: dict[tuple[int, str], datetime] = {}
purchased_products: dict[tuple[int, str], set[int]] = defaultdict(set)
detail_id = 1

for order_id, created_at in enumerate(order_times, start=1):
    user_id = rng.choices(user_ids, weights=user_weights, k=1)[0]
    status = status_values[order_id - 1]
    item_count = rng.choices([1, 2, 3], weights=[35, 50, 15], k=1)[0]
    selected = rng.sample(PRODUCTS, k=item_count)
    total_amount = Decimal("0.00")
    total_tokens = 0

    for p in selected:
        quantity = rng.choices([1, 2, 3], weights=[82, 14, 4], k=1)[0]
        subtotal = p.price * quantity
        item_tokens = p.token_amount * quantity
        total_amount += subtotal
        total_tokens += item_tokens
        order_details.append(
            {
                "detail_id": detail_id,
                "order_id": order_id,
                "product_id": p.product_id,
                "quantity": quantity,
                "unit_price": p.price,
                "subtotal": subtotal,
                "tokens_per_unit": p.token_amount,
                "total_tokens": item_tokens,
            }
        )
        detail_id += 1

        if status == "paid":
            key = (user_id, p.provider)
            credits[key] += item_tokens
            purchased_products[key].add(p.product_id)
            first_purchase[key] = min(first_purchase.get(key, created_at), created_at)

    paid_at = None
    if status in {"paid", "refunded"}:
        paid_at = created_at + timedelta(minutes=rng.randint(2, 45))

    orders.append(
        {
            "order_id": order_id,
            "user_id": user_id,
            "total_amount": total_amount,
            "total_tokens": total_tokens,
            "status": status,
            "created_at": created_at,
            "paid_at": paid_at,
        }
    )

usage_logs: list[dict[str, Any]] = []
end_for_usage = END - timedelta(minutes=30)
for _ in range(3000):
    candidates = [key for key, balance in credits.items() if balance >= 200]
    if not candidates:
        raise RuntimeError("Insufficient purchased token balance to generate 3000 usage rows.")

    weights = [max(1.0, credits[key] ** 0.45) for key in candidates]
    user_id, provider = rng.choices(candidates, weights=weights, k=1)[0]
    amount = rng.choices(
        [500, 800, 1000, 1500, 2000, 3000, 5000],
        weights=[8, 8, 18, 18, 20, 18, 10],
        k=1,
    )[0]
    tokens_used = min(amount, credits[(user_id, provider)])
    product_id = rng.choice(sorted(purchased_products[(user_id, provider)]))
    product = PRODUCT_BY_ID[product_id]
    account_id = rng.choice(ACCOUNTS_BY_PROVIDER[provider])
    upstream = math.ceil(
        tokens_used * product.required_upstream_tokens / product.token_amount
    )
    earliest = max(first_purchase[(user_id, provider)], START)
    used_at = random_datetime(earliest, end_for_usage)
    endpoint = rng.choices(
        ["/v1/chat/completions", "/v1/responses", "/v1/embeddings"],
        weights=[55, 30, 15],
        k=1,
    )[0]
    credits[(user_id, provider)] -= tokens_used
    usage_logs.append(
        {
            "user_id": user_id,
            "product_id": product_id,
            "account_id": account_id,
            "tokens_used": tokens_used,
            "upstream_tokens_consumed": upstream,
            "api_endpoint": endpoint,
            "used_at": used_at,
        }
    )

usage_logs.sort(key=lambda row: row["used_at"])
for log_id, row in enumerate(usage_logs, start=1):
    row["log_id"] = log_id

consumed_by_account: dict[int, int] = defaultdict(int)
for row in usage_logs:
    consumed_by_account[row["account_id"]] += row["upstream_tokens_consumed"]

reserve_by_account = {
    1: 300_000,
    2: 250_000,
    3: 450_000,
    4: 350_000,
    5: 500_000,
    6: 600_000,
    7: 400_000,
    8: 0,
}
task_plan = {
    1: ("low_quota", "api_recharge", 1_000_000, "completed"),
    2: ("low_quota", "manual_purchase", 800_000, "completed"),
    3: ("low_quota", "api_recharge", 1_000_000, "completed"),
    4: ("scheduled", "manual_purchase", 700_000, "completed"),
    5: ("scheduled", "api_recharge", 900_000, "pending"),
    6: ("manual", "manual_purchase", 600_000, "in_progress"),
    7: ("scheduled", "manual_purchase", 500_000, "failed"),
    8: ("low_quota", "api_recharge", 1_200_000, "failed"),
}

restock_tasks: list[dict[str, Any]] = []
completed_restock: dict[int, int] = defaultdict(int)
for account_id in range(1, 9):
    trigger, method, target, status = task_plan[account_id]
    actual = target if status == "completed" else None
    created_at = datetime(2026, 9, 18, 9, 0, 0) + timedelta(hours=account_id)
    completed_at = created_at + timedelta(minutes=30) if status == "completed" else None
    if actual is not None:
        completed_restock[account_id] += actual
    restock_tasks.append(
        {
            "task_id": account_id,
            "account_id": account_id,
            "trigger_reason": trigger,
            "restock_method": method,
            "target_amount": target,
            "actual_amount": actual,
            "created_by": 1,
            "assigned_to": 3 if status in {"completed", "in_progress"} else None,
            "status": status,
            "created_at": created_at,
            "completed_at": completed_at,
            "notes": f"教学合成补货任务 #{account_id}",
        }
    )

accounts: list[dict[str, Any]] = []
inventory: list[dict[str, Any]] = []
initial_purchase_by_account: dict[int, int] = {}
for account_id, provider, account_name, status in ACCOUNT_SPECS:
    consumed = consumed_by_account[account_id]
    initial_purchase = consumed + reserve_by_account[account_id]
    if initial_purchase <= 0:
        initial_purchase = 100_000
    initial_purchase_by_account[account_id] = initial_purchase
    total_quota = initial_purchase + completed_restock[account_id]
    current_quota = total_quota - consumed
    expires_at = (
        datetime(2026, 8, 31, 23, 59, 59)
        if status == "expired"
        else datetime(2027, 12, 31, 23, 59, 59)
    )
    accounts.append(
        {
            "account_id": account_id,
            "provider": provider,
            "account_name": account_name,
            "api_key": f"DEMO_NOT_A_REAL_API_KEY_{account_id:02d}",
            "total_quota": total_quota,
            "used_quota": consumed,
            "safety_threshold": 500_000,
            "status": status,
            "expires_at": expires_at,
            "created_at": datetime(2026, 6, 20, 8, 0, 0),
            "updated_at": END,
        }
    )
    inventory.append(
        {
            "inventory_id": account_id,
            "account_id": account_id,
            "current_quota": current_quota,
            "last_updated_at": END,
        }
    )

inventory_logs: list[dict[str, Any]] = []
inventory_log_id = 1
for account_id in range(1, 9):
    inventory_logs.append(
        {
            "log_id": inventory_log_id,
            "account_id": account_id,
            "change_type": "purchase",
            "change_amount": initial_purchase_by_account[account_id],
            "reference_id": None,
            "reference_type": None,
            "reason": "期初采购额度",
            "operator_id": 3,
            "created_at": datetime(2026, 6, 30, 12, 0, 0),
        }
    )
    inventory_log_id += 1

for usage in usage_logs:
    inventory_logs.append(
        {
            "log_id": inventory_log_id,
            "account_id": usage["account_id"],
            "change_type": "consumption",
            "change_amount": -usage["upstream_tokens_consumed"],
            "reference_id": usage["log_id"],
            "reference_type": "manual",
            "reason": f"API 调用消耗，对应 usage_log#{usage['log_id']}",
            "operator_id": None,
            "created_at": usage["used_at"],
        }
    )
    inventory_log_id += 1

for task in restock_tasks:
    if task["status"] == "completed":
        inventory_logs.append(
            {
                "log_id": inventory_log_id,
                "account_id": task["account_id"],
                "change_type": "restock",
                "change_amount": task["actual_amount"],
                "reference_id": task["task_id"],
                "reference_type": "restock_task",
                "reason": f"补货任务 #{task['task_id']} 完成",
                "operator_id": 3,
                "created_at": task["completed_at"],
            }
        )
        inventory_log_id += 1

token_balances: list[dict[str, Any]] = []
for balance_id, ((user_id, provider), remaining) in enumerate(
    sorted(credits.items()), start=1
):
    token_balances.append(
        {
            "balance_id": balance_id,
            "user_id": user_id,
            "model_provider": provider,
            "remaining_tokens": remaining,
            "updated_at": END,
        }
    )

summary_acc: dict[tuple[int, int, str, date, date], list[int]] = defaultdict(
    lambda: [0, 0, 0]
)
for row in usage_logs:
    used_date = row["used_at"].date()
    week_start = used_date - timedelta(days=used_date.weekday())
    week_end = week_start + timedelta(days=6)
    month_start = used_date.replace(day=1)
    if month_start.month == 12:
        next_month = date(month_start.year + 1, 1, 1)
    else:
        next_month = date(month_start.year, month_start.month + 1, 1)
    month_end = next_month - timedelta(days=1)

    periods = [
        ("daily", used_date, used_date),
        ("weekly", week_start, week_end),
        ("monthly", month_start, month_end),
    ]
    for period_type, period_start, period_end in periods:
        key = (
            row["user_id"],
            row["product_id"],
            period_type,
            period_start,
            period_end,
        )
        acc = summary_acc[key]
        acc[0] += row["tokens_used"]
        acc[1] += row["upstream_tokens_consumed"]
        acc[2] += 1

usage_summary: list[dict[str, Any]] = []
for summary_id, (key, values) in enumerate(sorted(summary_acc.items()), start=1):
    user_id, product_id, period_type, period_start, period_end = key
    last_date = min(period_end, END.date())
    usage_summary.append(
        {
            "summary_id": summary_id,
            "user_id": user_id,
            "product_id": product_id,
            "period_type": period_type,
            "period_start": period_start,
            "period_end": period_end,
            "total_tokens_used": values[0],
            "total_upstream_consumed": values[1],
            "request_count": values[2],
            "last_updated_at": datetime.combine(
                last_date, datetime.max.time()
            ).replace(microsecond=0),
        }
    )

exception_logs: list[dict[str, Any]] = []
exception_types = ["api_error", "inventory_error", "payment_error", "system_error"]
for exception_id in range(1, 16):
    kind = exception_types[(exception_id - 1) % len(exception_types)]
    sample_usage = rng.choice(usage_logs)
    if kind == "api_error":
        related_table = "TokenUsageLogs"
        related_id = sample_usage["log_id"]
        message = "API 调用失败：模拟速率限制"
        detail = "教学数据：用于演示异常记录与后续处理"
    elif kind == "inventory_error":
        related_table = "Inventory"
        related_id = sample_usage["account_id"]
        message = "库存检查异常：模拟额度接近阈值"
        detail = "教学数据：触发人工复核"
    elif kind == "payment_error":
        related_table = "Orders"
        related_id = rng.randint(1, 100)
        message = "支付回调异常：模拟状态同步失败"
        detail = "教学数据：订单状态需重新核对"
    else:
        related_table = None
        related_id = None
        message = "系统异常：模拟后台任务超时"
        detail = "教学数据：用于异常分类统计"

    result = rng.choice(["resolved", "ignored", "escalated"])
    occurred_at = sample_usage["used_at"] + timedelta(minutes=rng.randint(1, 15))
    handled_by = rng.randint(2, 5)
    exception_logs.append(
        {
            "exception_id": exception_id,
            "exception_type": kind,
            "related_table": related_table,
            "related_id": related_id,
            "error_message": message,
            "error_detail": detail,
            "occurred_at": occurred_at,
            "handled_by": handled_by,
            "handle_result": result,
            "handle_notes": "已按教学流程记录处理结果",
            "handled_at": occurred_at + timedelta(minutes=rng.randint(5, 90)),
        }
    )



def self_check() -> None:
    detail_by_order: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for row in order_details:
        detail_by_order[row["order_id"]].append(row)

    for order in orders:
        rows = detail_by_order[order["order_id"]]
        assert sum((r["subtotal"] for r in rows), Decimal("0.00")) == order["total_amount"]
        assert sum(r["total_tokens"] for r in rows) == order["total_tokens"]

    assert all(row["remaining_tokens"] >= 0 for row in token_balances)
    assert len(usage_logs) == 3000

    user_set = {row["user_id"] for row in users}
    product_set = {row["product_id"] for row in products}
    account_set = {row["account_id"] for row in accounts}
    employee_set = {row["employee_id"] for row in employees}
    order_set = {row["order_id"] for row in orders}

    for row in order_details:
        assert row["order_id"] in order_set
        assert row["product_id"] in product_set
    for row in usage_logs:
        assert row["user_id"] in user_set
        assert row["product_id"] in product_set
        assert row["account_id"] in account_set
        assert PRODUCT_BY_ID[row["product_id"]].provider == next(
            a["provider"] for a in accounts if a["account_id"] == row["account_id"]
        )
    for row in inventory_logs:
        assert row["account_id"] in account_set
        assert row["operator_id"] is None or row["operator_id"] in employee_set

    log_sum: dict[int, int] = defaultdict(int)
    for row in inventory_logs:
        log_sum[row["account_id"]] += row["change_amount"]
    inventory_by_account = {row["account_id"]: row for row in inventory}
    for account in accounts:
        account_id = account["account_id"]
        expected = account["total_quota"] - account["used_quota"]
        assert inventory_by_account[account_id]["current_quota"] == expected
        assert log_sum[account_id] == expected

    assert all(str(row["api_key"]).startswith("DEMO_NOT_A_REAL") for row in accounts)
    assert all(len(row["password_hash"]) == 60 for row in users)
    assert all(len(row["password_hash"]) == 60 for row in employees)


def sql_value(value: Any) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, Decimal):
        return format(value, "f")
    if isinstance(value, datetime):
        return "'" + value.strftime("%Y-%m-%d %H:%M:%S") + "'"
    if isinstance(value, date):
        return "'" + value.strftime("%Y-%m-%d") + "'"
    if isinstance(value, int):
        return str(value)
    text = str(value).replace("'", "''")
    return "N'" + text + "'"


def emit_identity(
    table: str,
    columns: list[str],
    rows: Iterable[dict[str, Any]],
    batch_size: int = 500,
) -> list[str]:
    materialized = list(rows)
    lines = [f"SET IDENTITY_INSERT dbo.{table} ON;", "GO"]
    for start in range(0, len(materialized), batch_size):
        batch = materialized[start : start + batch_size]
        lines.append(f"INSERT INTO dbo.{table} ({', '.join(columns)}) VALUES")
        rendered = []
        for row in batch:
            rendered.append(
                "    (" + ", ".join(sql_value(row[column]) for column in columns) + ")"
            )
        lines.append(",\n".join(rendered) + ";")
        lines.append("GO")
    lines.extend([f"SET IDENTITY_INSERT dbo.{table} OFF;", "GO", ""])
    return lines


def build_sql() -> str:
    sections: list[str] = [
        "-- Generated by tools/datagen.py",
        f"-- Fixed seed: {SEED}",
        "-- All credentials are non-secret teaching placeholders.",
        "-- Pricing direction was checked against provider API pricing on 2026-09-23;",
        "-- retail package prices are simplified for this database experiment.",
        "",
        "USE [TokenHubDB_Week3];",
        "GO",
        "SET NOCOUNT ON;",
        "SET XACT_ABORT ON;",
        "BEGIN TRANSACTION;",
        "GO",
        "",
    ]

    table_specs = [
        ("Roles", ["role_id", "role_name", "description", "permissions"], roles),
        (
            "Users",
            ["user_id", "username", "password_hash", "email", "phone", "status", "created_at", "updated_at"],
            users,
        ),
        (
            "Products",
            ["product_id", "name", "description", "price", "model_provider", "token_amount", "required_upstream_tokens", "status", "created_at"],
            products,
        ),
        (
            "UpstreamAccount",
            ["account_id", "provider", "account_name", "api_key", "total_quota", "used_quota", "safety_threshold", "status", "expires_at", "created_at", "updated_at"],
            accounts,
        ),
        ("Inventory", ["inventory_id", "account_id", "current_quota", "last_updated_at"], inventory),
        (
            "Employees",
            ["employee_id", "name", "role_id", "account", "password_hash", "hire_date", "status"],
            employees,
        ),
        (
            "Orders",
            ["order_id", "user_id", "total_amount", "total_tokens", "status", "created_at", "paid_at"],
            orders,
        ),
        (
            "OrderDetails",
            ["detail_id", "order_id", "product_id", "quantity", "unit_price", "subtotal", "tokens_per_unit", "total_tokens"],
            order_details,
        ),
        (
            "InventoryLog",
            ["log_id", "account_id", "change_type", "change_amount", "reference_id", "reference_type", "reason", "operator_id", "created_at"],
            inventory_logs,
        ),
        (
            "TokenBalances",
            ["balance_id", "user_id", "model_provider", "remaining_tokens", "updated_at"],
            token_balances,
        ),
        (
            "TokenUsageLogs",
            ["log_id", "user_id", "product_id", "account_id", "tokens_used", "upstream_tokens_consumed", "api_endpoint", "used_at"],
            usage_logs,
        ),
        (
            "UsageSummary",
            ["summary_id", "user_id", "product_id", "period_type", "period_start", "period_end", "total_tokens_used", "total_upstream_consumed", "request_count", "last_updated_at"],
            usage_summary,
        ),
        (
            "RestockTask",
            ["task_id", "account_id", "trigger_reason", "restock_method", "target_amount", "actual_amount", "created_by", "assigned_to", "status", "created_at", "completed_at", "notes"],
            restock_tasks,
        ),
        (
            "ExceptionLog",
            ["exception_id", "exception_type", "related_table", "related_id", "error_message", "error_detail", "occurred_at", "handled_by", "handle_result", "handle_notes", "handled_at"],
            exception_logs,
        ),
    ]

    for table, columns, rows in table_specs:
        sections.extend(emit_identity(table, columns, rows))

    sections.extend(
        [
            "COMMIT TRANSACTION;",
            "GO",
            "",
            "SELECT N'Data load completed' AS message;",
            "GO",
        ]
    )
    return "\n".join(sections)


def main() -> None:
    self_check()
    sql_text = build_sql()
    OUT_PATH.write_text(sql_text, encoding="utf-8")
    counts = {
        "Users": len(users),
        "Products": len(products),
        "UpstreamAccount": len(accounts),
        "Inventory": len(inventory),
        "Employees": len(employees),
        "Orders": len(orders),
        "OrderDetails": len(order_details),
        "InventoryLog": len(inventory_logs),
        "TokenBalances": len(token_balances),
        "TokenUsageLogs": len(usage_logs),
        "UsageSummary": len(usage_summary),
        "RestockTask": len(restock_tasks),
        "ExceptionLog": len(exception_logs),
    }
    print(f"seed={SEED}")
    print(f"output={OUT_PATH}")
    for table, count in counts.items():
        print(f"{table}={count}")
    print("self_check=PASS")


if __name__ == "__main__":
    main()
