"""验证交易时间线；最终余额正确不能替代逐事件余额检查。"""

from collections import defaultdict
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import TypeAlias

Scalar: TypeAlias = str | int | bool | Decimal | date | datetime | None
Row: TypeAlias = dict[str, Scalar]
Tables: TypeAlias = dict[str, list[Row]]
Event: TypeAlias = tuple[datetime, int, int, str, int, int]


def number(row: Row, key: str) -> int:
    value = row[key]
    if not isinstance(value, int):
        raise ValueError(f"{key} 必须是 int")
    return value


def moment(row: Row, key: str) -> datetime:
    value = row[key]
    if not isinstance(value, datetime):
        raise ValueError(f"{key} 必须是 datetime")
    return value


def text(row: Row, key: str) -> str:
    value = row[key]
    if not isinstance(value, str):
        raise ValueError(f"{key} 必须是 str")
    return value


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def credit_events(orders: list[Row], details: list[Row], products: list[Row]) -> list[Event]:
    headers = {number(row, "order_id"): row for row in orders}
    catalog = {number(row, "product_id"): row for row in products}
    events: list[Event] = []
    for detail in details:
        order = headers[number(detail, "order_id")]
        if order["status"] != "paid":
            continue
        product = catalog[number(detail, "product_id")]
        events.append(
            (
                moment(order, "paid_at"),
                0,
                number(order, "user_id"),
                text(product, "model_provider"),
                number(detail, "total_tokens"),
                number(detail, "detail_id"),
            )
        )
    return events


def repair_timeline(
    users: list[Row],
    orders: list[Row],
    details: list[Row],
    products: list[Row],
    usage: list[Row],
) -> None:
    """保留业务金额和用量，仅将消费安排到累计已付款额度足够的时刻。"""
    members = {number(row, "user_id"): row for row in users}
    catalog = {number(row, "product_id"): row for row in products}
    for order in orders:
        member = members[number(order, "user_id")]
        member["created_at"] = min(
            moment(member, "created_at"),
            moment(order, "created_at") - timedelta(seconds=1),
        )
    funding: dict[tuple[int, str], list[tuple[datetime, int]]] = defaultdict(list)
    for when, _, user, provider, amount, _ in sorted(credit_events(orders, details, products)):
        previous = funding[(user, provider)][-1][1] if funding[(user, provider)] else 0
        funding[(user, provider)].append((when, previous + amount))
    spent: dict[tuple[int, str], int] = defaultdict(int)
    for row in sorted(usage, key=lambda item: moment(item, "used_at")):
        key = (
            number(row, "user_id"),
            text(catalog[number(row, "product_id")], "model_provider"),
        )
        spent[key] += number(row, "tokens_used")
        funded_at = next((when for when, total in funding[key] if total >= spent[key]), None)
        require(funded_at is not None, "已付款额度不足，无法安排调用")
        if funded_at is None:
            raise ValueError("缺少付款事件")
        row["used_at"] = max(moment(row, "used_at"), funded_at)


def valid_at(account: Row, when: datetime) -> bool:
    expiry = account["expires_at"]
    return moment(account, "created_at") <= when and (
        expiry is None or (isinstance(expiry, datetime) and when < expiry)
    )


def repair_accounts(usage: list[Row], accounts: list[Row], products: list[Row]) -> None:
    """快照中的 expired/suspended 不能推断历史状态，仅按明确的有效期筛选。"""
    pool = {number(row, "account_id"): row for row in accounts}
    catalog = {number(row, "product_id"): row for row in products}
    for row in usage:
        when = moment(row, "used_at")
        provider = text(catalog[number(row, "product_id")], "model_provider")
        account = pool.get(number(row, "account_id"))
        if account is not None and account["provider"] == provider and valid_at(account, when):
            continue
        candidates = [
            candidate
            for candidate in accounts
            if candidate["provider"] == provider and valid_at(candidate, when)
        ]
        require(bool(candidates), "调用时没有同 provider 的有效账号")
        row["account_id"] = number(candidates[0], "account_id")


def validate_timeline(tables: Tables) -> None:
    users = {number(row, "user_id"): row for row in tables["Users"]}
    products = {number(row, "product_id"): row for row in tables["Products"]}
    accounts = {number(row, "account_id"): row for row in tables["UpstreamAccount"]}
    for order in tables["Orders"]:
        require(
            moment(order, "created_at") >= moment(users[number(order, "user_id")], "created_at"),
            "订单早于注册",
        )
        if order["status"] in ("paid", "refunded"):
            require(moment(order, "paid_at") >= moment(order, "created_at"), "付款早于订单")
        else:
            require(order["paid_at"] is None, "未支付订单包含付款时间")
    events = credit_events(tables["Orders"], tables["OrderDetails"], tables["Products"])
    for row in tables["TokenUsageLogs"]:
        user, when = number(row, "user_id"), moment(row, "used_at")
        account = accounts[number(row, "account_id")]
        provider = text(products[number(row, "product_id")], "model_provider")
        require(when >= moment(users[user], "created_at"), "调用早于注册")
        require(account["provider"] == provider, "调用 provider 不匹配")
        require(valid_at(account, when), "调用不在账号有效期内")
        events.append(
            (
                when,
                1,
                user,
                provider,
                -number(row, "tokens_used"),
                number(row, "log_id"),
            )
        )
    balances: dict[tuple[int, str], int] = defaultdict(int)
    for _, _, user, provider, change, _ in sorted(events):
        balances[(user, provider)] += change
        require(balances[(user, provider)] >= 0, "历史余额为负")
    actual = {
        (number(row, "user_id"), text(row, "model_provider")): number(row, "remaining_tokens")
        for row in tables["TokenBalances"]
    }
    require(dict(balances) == actual, "最终余额与时间线不一致")


def validate_relationships(tables: Tables) -> None:
    grouped: dict[int, list[Row]] = defaultdict(list)
    for row in tables["OrderDetails"]:
        grouped[number(row, "order_id")].append(row)
        require(
            row["subtotal"] == number(row, "quantity") * row["unit_price"],
            "明细金额错误",
        )
        require(
            number(row, "total_tokens") == number(row, "quantity") * number(row, "tokens_per_unit"),
            "明细 Token 错误",
        )
    for order in tables["Orders"]:
        details = grouped[number(order, "order_id")]
        require(bool(details), "订单没有明细")
        require(
            sum((row["subtotal"] for row in details), Decimal(0)) == order["total_amount"],
            "订单头与明细金额不一致",
        )
        require(
            sum(number(row, "total_tokens") for row in details) == number(order, "total_tokens"),
            "订单头与明细 Token 不一致",
        )
    movement: dict[int, int] = defaultdict(int)
    for row in tables["InventoryLog"]:
        movement[number(row, "account_id")] += number(row, "change_amount")
    stock = {number(row, "account_id"): row for row in tables["Inventory"]}
    for row in tables["UpstreamAccount"]:
        key = number(row, "account_id")
        quota = number(row, "total_quota") - number(row, "used_quota")
        require(
            quota >= 0 and number(stock[key], "current_quota") == quota == movement[key],
            "账号、库存与流水不一致",
        )
        require(text(row, "api_key").startswith("DEMO_NOT_A_REAL"), "样例必须使用教学占位符")


def validate_dataset(tables: Tables) -> None:
    validate_references(tables)
    validate_relationships(tables)
    validate_timeline(tables)


def validate_references(tables: Tables) -> None:
    """序列化前拒绝缺失父实体，不能仅依赖后续 SQL 装载时报错。"""
    relations = [
        ("Orders", "user_id", "Users", "user_id"),
        ("OrderDetails", "order_id", "Orders", "order_id"),
        ("OrderDetails", "product_id", "Products", "product_id"),
        ("Employees", "role_id", "Roles", "role_id"),
        ("Inventory", "account_id", "UpstreamAccount", "account_id"),
        ("InventoryLog", "account_id", "UpstreamAccount", "account_id"),
        ("InventoryLog", "operator_id", "Employees", "employee_id"),
        ("TokenUsageLogs", "user_id", "Users", "user_id"),
        ("TokenUsageLogs", "product_id", "Products", "product_id"),
        ("TokenUsageLogs", "account_id", "UpstreamAccount", "account_id"),
        ("TokenBalances", "user_id", "Users", "user_id"),
        ("UsageSummary", "user_id", "Users", "user_id"),
        ("UsageSummary", "product_id", "Products", "product_id"),
        ("RestockTask", "account_id", "UpstreamAccount", "account_id"),
        ("RestockTask", "created_by", "Employees", "employee_id"),
        ("RestockTask", "assigned_to", "Employees", "employee_id"),
        ("ExceptionLog", "handled_by", "Employees", "employee_id"),
    ]
    for child, foreign_key, parent, primary_key in relations:
        keys = {number(row, primary_key) for row in tables[parent]}
        for row in tables[child]:
            require(
                row[foreign_key] is None or row[foreign_key] in keys,
                f"{child}.{foreign_key} 引用不存在的 {parent}",
            )
    for row in tables["Users"] + tables["Employees"]:
        require(len(text(row, "password_hash")) == 60, "样例密码哈希长度必须为 60")
