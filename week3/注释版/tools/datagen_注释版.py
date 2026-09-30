"""第三周数据库实验：合成数据生成器（注释版）。

这个文件有三个目标：
1. 使用固定随机种子生成可复现的课程实验数据；
2. 保证订单、Token 余额、上游库存、库存流水和汇总表之间保持业务一致；
3. 把生成结果写成可直接由 SQL Server 执行的 02_insert_data.sql。

代码按下面的顺序组织：
1. 导入标准库、固定随机种子和输出路径
2. 定义商品与上游账号基础配置
3. 生成角色、用户、商品、员工和订单数据
4. 根据已支付订单生成 Token 使用、库存、补货与异常数据
5. 执行业务一致性 self_check
6. 把 Python 数据结构转换成 SQL INSERT 语句
7. main() 写出最终 SQL 文件并打印数据量
"""

from __future__ import annotations  # 作用：启用现代类型注解行为，便于后面直接使用新的类型写法

import math  # 作用：导入后续数据生成、随机数或文件处理所需模块或对象
import random  # 作用：导入后续数据生成、随机数或文件处理所需模块或对象
from collections import defaultdict  # 作用：导入后续数据生成、随机数或文件处理所需模块或对象
from dataclasses import dataclass  # 作用：导入后续数据生成、随机数或文件处理所需模块或对象
from datetime import date, datetime, timedelta  # 作用：导入后续数据生成、随机数或文件处理所需模块或对象
from decimal import Decimal  # 作用：导入后续数据生成、随机数或文件处理所需模块或对象
from pathlib import Path  # 作用：导入后续数据生成、随机数或文件处理所需模块或对象
from typing import Any, Iterable  # 作用：导入后续数据生成、随机数或文件处理所需模块或对象

SEED = 20260923  # 作用：定义固定配置或全局常量，供后续生成流程统一使用
rng = random.Random(SEED)  # 作用：计算或保存右侧结果，供后续步骤继续使用
START = datetime(2026, 7, 1, 0, 0, 0)  # 作用：定义固定配置或全局常量，供后续生成流程统一使用
END = datetime(2026, 9, 22, 23, 59, 59)  # 作用：定义固定配置或全局常量，供后续生成流程统一使用
OUT_PATH = Path(__file__).resolve().parents[1] / "sql" / "02_insert_data.sql"  # 作用：定义固定配置或全局常量，供后续生成流程统一使用


@dataclass(frozen=True)  # 作用：把下面的类声明为 dataclass，自动生成初始化等基础方法
class ProductSpec:  # 作用：定义 ProductSpec 数据结构，集中保存一类固定配置
    product_id: int  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    name: str  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    price: Decimal  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    provider: str  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    token_amount: int  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    required_upstream_tokens: int  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    status: str = "active"  # 作用：计算或保存右侧结果，供后续步骤继续使用


PRODUCTS = [  # 作用：定义固定配置或全局常量，供后续生成流程统一使用
    ProductSpec(1, "OpenAI 50K Token包", Decimal("3.90"), "OpenAI", 50_000, 60_000),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    ProductSpec(2, "OpenAI 100K Token包", Decimal("6.90"), "OpenAI", 100_000, 120_000),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    ProductSpec(3, "OpenAI 500K Token包", Decimal("31.90"), "OpenAI", 500_000, 600_000),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    ProductSpec(4, "OpenAI 1M Token包", Decimal("59.90"), "OpenAI", 1_000_000, 1_200_000),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    ProductSpec(5, "Claude 100K Token包", Decimal("6.90"), "Claude", 100_000, 120_000),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    ProductSpec(6, "Claude 500K Token包", Decimal("31.90"), "Claude", 500_000, 600_000),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    ProductSpec(7, "Claude 1M Token包", Decimal("59.90"), "Claude", 1_000_000, 1_200_000),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    ProductSpec(8, "Gemini 100K Token包", Decimal("1.90"), "Gemini", 100_000, 120_000),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    ProductSpec(9, "Gemini 500K Token包", Decimal("7.90"), "Gemini", 500_000, 600_000),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    ProductSpec(10, "Gemini 1M Token包", Decimal("14.90"), "Gemini", 1_000_000, 1_200_000),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
]
PRODUCT_BY_ID = {p.product_id: p for p in PRODUCTS}  # 作用：定义固定配置或全局常量，供后续生成流程统一使用

ACCOUNT_SPECS = [  # 作用：定义固定配置或全局常量，供后续生成流程统一使用
    (1, "OpenAI", "OpenAI-池-01", "active"),
    (2, "OpenAI", "OpenAI-池-02", "active"),
    (3, "OpenAI", "OpenAI-池-03", "active"),
    (4, "Claude", "Claude-池-01", "active"),
    (5, "Claude", "Claude-池-02", "active"),
    (6, "Claude", "Claude-池-03", "suspended"),
    (7, "Gemini", "Gemini-池-01", "expired"),
    (8, "Gemini", "Gemini-池-02", "depleted"),
]
ACCOUNTS_BY_PROVIDER: dict[str, list[int]] = defaultdict(list)  # 作用：计算或保存右侧结果，供后续步骤继续使用
for account_id, provider, _, _ in ACCOUNT_SPECS:  # 作用：遍历当前集合，逐项生成、统计或校验数据
    ACCOUNTS_BY_PROVIDER[provider].append(account_id)  # 作用：把当前生成的一条记录追加到目标列表


def bcrypt_placeholder(prefix: str, number: int) -> str:  # 作用：定义 bcrypt_placeholder 函数，封装这一段可重复调用的逻辑
    body = f"{prefix}{number:02d}".ljust(53, "x")[:53]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    value = "$2b$12$" + body  # 作用：计算或保存右侧结果，供后续步骤继续使用
    assert len(value) == 60  # 作用：执行一致性断言，不满足条件时立即暴露生成错误
    return value  # 作用：把当前函数的计算结果返回给调用者


def random_datetime(start: datetime, end: datetime) -> datetime:  # 作用：定义 random_datetime 函数，封装这一段可重复调用的逻辑
    seconds = int((end - start).total_seconds())  # 作用：计算或保存右侧结果，供后续步骤继续使用
    return start + timedelta(seconds=rng.randint(0, seconds))  # 作用：把当前函数的计算结果返回给调用者


def order_datetime() -> datetime:  # 作用：定义 order_datetime 函数，封装这一段可重复调用的逻辑
    while True:  # 作用：持续循环直到生成满足业务条件的数据
        day = START.date() + timedelta(days=rng.randint(0, (END.date() - START.date()).days))  # 作用：计算或保存右侧结果，供后续步骤继续使用
        if day.weekday() >= 5 and rng.random() < 0.55:  # 作用：检查当前条件是否成立，成立时进入对应分支
            continue  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        hour = rng.choices(  # 作用：计算或保存右侧结果，供后续步骤继续使用
            [9, 10, 11, 14, 15, 16, 17, 20, 21, 22],
            weights=[8, 10, 8, 8, 10, 10, 8, 7, 7, 5],  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            k=1,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        )[0]
        return datetime.combine(day, datetime.min.time()).replace(  # 作用：把当前函数的计算结果返回给调用者
            hour=hour,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            minute=rng.randint(0, 59),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            second=rng.randint(0, 59),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        )


roles = [  # 作用：计算或保存右侧结果，供后续步骤继续使用
    {
        "role_id": 1,  # 作用：定义当前记录的一个字段及其对应值
        "role_name": "admin",  # 作用：定义当前记录的一个字段及其对应值
        "description": "系统管理员，拥有全部应用层管理权限",  # 作用：定义当前记录的一个字段及其对应值
        "permissions": '{"all": true}',  # 作用：定义当前记录的一个字段及其对应值
    },
    {
        "role_id": 2,  # 作用：定义当前记录的一个字段及其对应值
        "role_name": "staff",  # 作用：定义当前记录的一个字段及其对应值
        "description": "客服与运营人员",  # 作用：定义当前记录的一个字段及其对应值
        "permissions": '{"orders":"read/write","users":"read","inventory":"read"}',  # 作用：定义当前记录的一个字段及其对应值
    },
    {
        "role_id": 3,  # 作用：定义当前记录的一个字段及其对应值
        "role_name": "customer",  # 作用：定义当前记录的一个字段及其对应值
        "description": "普通用户",  # 作用：定义当前记录的一个字段及其对应值
        "permissions": '{"products":"read","orders":"create","balance":"read"}',  # 作用：定义当前记录的一个字段及其对应值
    },
]

users: list[dict[str, Any]] = []  # 作用：计算或保存右侧结果，供后续步骤继续使用
for user_id in range(1, 41):  # 作用：遍历当前集合，逐项生成、统计或校验数据
    status = "active" if user_id <= 35 else ("frozen" if user_id <= 39 else "deleted")  # 作用：计算或保存右侧结果，供后续步骤继续使用
    created_at = random_datetime(datetime(2026, 5, 1), datetime(2026, 8, 31))  # 作用：计算或保存右侧结果，供后续步骤继续使用
    users.append(  # 作用：把当前生成的一条记录追加到目标列表
        {
            "user_id": user_id,  # 作用：定义当前记录的一个字段及其对应值
            "username": f"user{user_id:03d}",  # 作用：定义当前记录的一个字段及其对应值
            "password_hash": bcrypt_placeholder("u", user_id),  # 作用：定义当前记录的一个字段及其对应值
            "email": f"user{user_id:03d}@example.edu",  # 作用：定义当前记录的一个字段及其对应值
            "phone": None if user_id % 7 == 0 else f"138{user_id:08d}",  # 作用：定义当前记录的一个字段及其对应值
            "status": status,  # 作用：定义当前记录的一个字段及其对应值
            "created_at": created_at,  # 作用：定义当前记录的一个字段及其对应值
            "updated_at": created_at + timedelta(days=rng.randint(0, 20)),  # 作用：定义当前记录的一个字段及其对应值
        }
    )

products = [  # 作用：计算或保存右侧结果，供后续步骤继续使用
    {
        "product_id": p.product_id,  # 作用：定义当前记录的一个字段及其对应值
        "name": p.name,  # 作用：定义当前记录的一个字段及其对应值
        "description": f"{p.provider} API Token 虚拟套餐；教学用合成商品。",  # 作用：定义当前记录的一个字段及其对应值
        "price": p.price,  # 作用：定义当前记录的一个字段及其对应值
        "model_provider": p.provider,  # 作用：定义当前记录的一个字段及其对应值
        "token_amount": p.token_amount,  # 作用：定义当前记录的一个字段及其对应值
        "required_upstream_tokens": p.required_upstream_tokens,  # 作用：定义当前记录的一个字段及其对应值
        "status": p.status,  # 作用：定义当前记录的一个字段及其对应值
        "created_at": datetime(2026, 6, 20, 9, 0, 0),  # 作用：定义当前记录的一个字段及其对应值
    }
    for p in PRODUCTS  # 作用：遍历当前集合，逐项生成、统计或校验数据
]

employees = [  # 作用：计算或保存右侧结果，供后续步骤继续使用
    {
        "employee_id": 1,  # 作用：定义当前记录的一个字段及其对应值
        "name": "张经理",  # 作用：定义当前记录的一个字段及其对应值
        "role_id": 1,  # 作用：定义当前记录的一个字段及其对应值
        "account": "admin_zhang",  # 作用：定义当前记录的一个字段及其对应值
        "password_hash": bcrypt_placeholder("e", 1),  # 作用：定义当前记录的一个字段及其对应值
        "hire_date": date(2026, 1, 5),  # 作用：定义当前记录的一个字段及其对应值
        "status": "active",  # 作用：定义当前记录的一个字段及其对应值
    },
    {
        "employee_id": 2,  # 作用：定义当前记录的一个字段及其对应值
        "name": "李客服",  # 作用：定义当前记录的一个字段及其对应值
        "role_id": 2,  # 作用：定义当前记录的一个字段及其对应值
        "account": "staff_li",  # 作用：定义当前记录的一个字段及其对应值
        "password_hash": bcrypt_placeholder("e", 2),  # 作用：定义当前记录的一个字段及其对应值
        "hire_date": date(2026, 3, 15),  # 作用：定义当前记录的一个字段及其对应值
        "status": "active",  # 作用：定义当前记录的一个字段及其对应值
    },
    {
        "employee_id": 3,  # 作用：定义当前记录的一个字段及其对应值
        "name": "王运营",  # 作用：定义当前记录的一个字段及其对应值
        "role_id": 2,  # 作用：定义当前记录的一个字段及其对应值
        "account": "staff_wang",  # 作用：定义当前记录的一个字段及其对应值
        "password_hash": bcrypt_placeholder("e", 3),  # 作用：定义当前记录的一个字段及其对应值
        "hire_date": date(2026, 4, 20),  # 作用：定义当前记录的一个字段及其对应值
        "status": "active",  # 作用：定义当前记录的一个字段及其对应值
    },
    {
        "employee_id": 4,  # 作用：定义当前记录的一个字段及其对应值
        "name": "赵客服",  # 作用：定义当前记录的一个字段及其对应值
        "role_id": 2,  # 作用：定义当前记录的一个字段及其对应值
        "account": "staff_zhao",  # 作用：定义当前记录的一个字段及其对应值
        "password_hash": bcrypt_placeholder("e", 4),  # 作用：定义当前记录的一个字段及其对应值
        "hire_date": date(2026, 5, 12),  # 作用：定义当前记录的一个字段及其对应值
        "status": "active",  # 作用：定义当前记录的一个字段及其对应值
    },
    {
        "employee_id": 5,  # 作用：定义当前记录的一个字段及其对应值
        "name": "钱运营",  # 作用：定义当前记录的一个字段及其对应值
        "role_id": 2,  # 作用：定义当前记录的一个字段及其对应值
        "account": "staff_qian",  # 作用：定义当前记录的一个字段及其对应值
        "password_hash": bcrypt_placeholder("e", 5),  # 作用：定义当前记录的一个字段及其对应值
        "hire_date": date(2026, 6, 8),  # 作用：定义当前记录的一个字段及其对应值
        "status": "active",  # 作用：定义当前记录的一个字段及其对应值
    },
    {
        "employee_id": 6,  # 作用：定义当前记录的一个字段及其对应值
        "name": "孙客服",  # 作用：定义当前记录的一个字段及其对应值
        "role_id": 2,  # 作用：定义当前记录的一个字段及其对应值
        "account": "staff_sun",  # 作用：定义当前记录的一个字段及其对应值
        "password_hash": bcrypt_placeholder("e", 6),  # 作用：定义当前记录的一个字段及其对应值
        "hire_date": date(2026, 6, 25),  # 作用：定义当前记录的一个字段及其对应值
        "status": "inactive",  # 作用：定义当前记录的一个字段及其对应值
    },
]

status_values = ["paid"] * 85 + ["pending"] * 8 + ["cancelled"] * 5 + ["refunded"] * 2  # 作用：计算或保存右侧结果，供后续步骤继续使用
rng.shuffle(status_values)  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
order_times = sorted(order_datetime() for _ in range(100))  # 作用：计算或保存右侧结果，供后续步骤继续使用
user_ids = list(range(1, 36))  # 作用：计算或保存右侧结果，供后续步骤继续使用
user_weights = [1.0 / (uid ** 0.55) for uid in user_ids]  # 作用：计算或保存右侧结果，供后续步骤继续使用

orders: list[dict[str, Any]] = []  # 作用：计算或保存右侧结果，供后续步骤继续使用
order_details: list[dict[str, Any]] = []  # 作用：计算或保存右侧结果，供后续步骤继续使用
credits: dict[tuple[int, str], int] = defaultdict(int)  # 作用：计算或保存右侧结果，供后续步骤继续使用
first_purchase: dict[tuple[int, str], datetime] = {}  # 作用：计算或保存右侧结果，供后续步骤继续使用
purchased_products: dict[tuple[int, str], set[int]] = defaultdict(set)  # 作用：计算或保存右侧结果，供后续步骤继续使用
detail_id = 1  # 作用：计算或保存右侧结果，供后续步骤继续使用

for order_id, created_at in enumerate(order_times, start=1):  # 作用：遍历当前集合，逐项生成、统计或校验数据
    user_id = rng.choices(user_ids, weights=user_weights, k=1)[0]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    status = status_values[order_id - 1]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    item_count = rng.choices([1, 2, 3], weights=[35, 50, 15], k=1)[0]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    selected = rng.sample(PRODUCTS, k=item_count)  # 作用：计算或保存右侧结果，供后续步骤继续使用
    total_amount = Decimal("0.00")  # 作用：计算或保存右侧结果，供后续步骤继续使用
    total_tokens = 0  # 作用：计算或保存右侧结果，供后续步骤继续使用

    for p in selected:  # 作用：遍历当前集合，逐项生成、统计或校验数据
        quantity = rng.choices([1, 2, 3], weights=[82, 14, 4], k=1)[0]  # 作用：计算或保存右侧结果，供后续步骤继续使用
        subtotal = p.price * quantity  # 作用：计算或保存右侧结果，供后续步骤继续使用
        item_tokens = p.token_amount * quantity  # 作用：计算或保存右侧结果，供后续步骤继续使用
        total_amount += subtotal  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        total_tokens += item_tokens  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        order_details.append(  # 作用：把当前生成的一条记录追加到目标列表
            {
                "detail_id": detail_id,  # 作用：定义当前记录的一个字段及其对应值
                "order_id": order_id,  # 作用：定义当前记录的一个字段及其对应值
                "product_id": p.product_id,  # 作用：定义当前记录的一个字段及其对应值
                "quantity": quantity,  # 作用：定义当前记录的一个字段及其对应值
                "unit_price": p.price,  # 作用：定义当前记录的一个字段及其对应值
                "subtotal": subtotal,  # 作用：定义当前记录的一个字段及其对应值
                "tokens_per_unit": p.token_amount,  # 作用：定义当前记录的一个字段及其对应值
                "total_tokens": item_tokens,  # 作用：定义当前记录的一个字段及其对应值
            }
        )
        detail_id += 1  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑

        if status == "paid":  # 作用：检查当前条件是否成立，成立时进入对应分支
            key = (user_id, p.provider)  # 作用：计算或保存右侧结果，供后续步骤继续使用
            credits[key] += item_tokens  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            purchased_products[key].add(p.product_id)  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            first_purchase[key] = min(first_purchase.get(key, created_at), created_at)  # 作用：计算或保存右侧结果，供后续步骤继续使用

    paid_at = None  # 作用：计算或保存右侧结果，供后续步骤继续使用
    if status in {"paid", "refunded"}:  # 作用：检查当前条件是否成立，成立时进入对应分支
        paid_at = created_at + timedelta(minutes=rng.randint(2, 45))  # 作用：计算或保存右侧结果，供后续步骤继续使用

    orders.append(  # 作用：把当前生成的一条记录追加到目标列表
        {
            "order_id": order_id,  # 作用：定义当前记录的一个字段及其对应值
            "user_id": user_id,  # 作用：定义当前记录的一个字段及其对应值
            "total_amount": total_amount,  # 作用：定义当前记录的一个字段及其对应值
            "total_tokens": total_tokens,  # 作用：定义当前记录的一个字段及其对应值
            "status": status,  # 作用：定义当前记录的一个字段及其对应值
            "created_at": created_at,  # 作用：定义当前记录的一个字段及其对应值
            "paid_at": paid_at,  # 作用：定义当前记录的一个字段及其对应值
        }
    )

usage_logs: list[dict[str, Any]] = []  # 作用：计算或保存右侧结果，供后续步骤继续使用
end_for_usage = END - timedelta(minutes=30)  # 作用：计算或保存右侧结果，供后续步骤继续使用
for _ in range(3000):  # 作用：遍历当前集合，逐项生成、统计或校验数据
    candidates = [key for key, balance in credits.items() if balance >= 200]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    if not candidates:  # 作用：检查当前条件是否成立，成立时进入对应分支
        raise RuntimeError("Insufficient purchased token balance to generate 3000 usage rows.")  # 作用：主动抛出异常，阻止不合法状态继续执行

    weights = [max(1.0, credits[key] ** 0.45) for key in candidates]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    user_id, provider = rng.choices(candidates, weights=weights, k=1)[0]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    amount = rng.choices(  # 作用：计算或保存右侧结果，供后续步骤继续使用
        [500, 800, 1000, 1500, 2000, 3000, 5000],
        weights=[8, 8, 18, 18, 20, 18, 10],  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        k=1,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    )[0]
    tokens_used = min(amount, credits[(user_id, provider)])  # 作用：计算或保存右侧结果，供后续步骤继续使用
    product_id = rng.choice(sorted(purchased_products[(user_id, provider)]))  # 作用：计算或保存右侧结果，供后续步骤继续使用
    product = PRODUCT_BY_ID[product_id]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    account_id = rng.choice(ACCOUNTS_BY_PROVIDER[provider])  # 作用：计算或保存右侧结果，供后续步骤继续使用
    upstream = math.ceil(  # 作用：计算或保存右侧结果，供后续步骤继续使用
        tokens_used * product.required_upstream_tokens / product.token_amount  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    )
    earliest = max(first_purchase[(user_id, provider)], START)  # 作用：计算或保存右侧结果，供后续步骤继续使用
    used_at = random_datetime(earliest, end_for_usage)  # 作用：计算或保存右侧结果，供后续步骤继续使用
    endpoint = rng.choices(  # 作用：计算或保存右侧结果，供后续步骤继续使用
        ["/v1/chat/completions", "/v1/responses", "/v1/embeddings"],
        weights=[55, 30, 15],  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        k=1,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    )[0]
    credits[(user_id, provider)] -= tokens_used  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    usage_logs.append(  # 作用：把当前生成的一条记录追加到目标列表
        {
            "user_id": user_id,  # 作用：定义当前记录的一个字段及其对应值
            "product_id": product_id,  # 作用：定义当前记录的一个字段及其对应值
            "account_id": account_id,  # 作用：定义当前记录的一个字段及其对应值
            "tokens_used": tokens_used,  # 作用：定义当前记录的一个字段及其对应值
            "upstream_tokens_consumed": upstream,  # 作用：定义当前记录的一个字段及其对应值
            "api_endpoint": endpoint,  # 作用：定义当前记录的一个字段及其对应值
            "used_at": used_at,  # 作用：定义当前记录的一个字段及其对应值
        }
    )

usage_logs.sort(key=lambda row: row["used_at"])  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
for log_id, row in enumerate(usage_logs, start=1):  # 作用：遍历当前集合，逐项生成、统计或校验数据
    row["log_id"] = log_id  # 作用：计算或保存右侧结果，供后续步骤继续使用

consumed_by_account: dict[int, int] = defaultdict(int)  # 作用：计算或保存右侧结果，供后续步骤继续使用
for row in usage_logs:  # 作用：遍历当前集合，逐项生成、统计或校验数据
    consumed_by_account[row["account_id"]] += row["upstream_tokens_consumed"]  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑

reserve_by_account = {  # 作用：计算或保存右侧结果，供后续步骤继续使用
    1: 300_000,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    2: 250_000,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    3: 450_000,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    4: 350_000,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    5: 500_000,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    6: 600_000,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    7: 400_000,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    8: 0,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
}
task_plan = {  # 作用：计算或保存右侧结果，供后续步骤继续使用
    1: ("low_quota", "api_recharge", 1_000_000, "completed"),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    2: ("low_quota", "manual_purchase", 800_000, "completed"),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    3: ("low_quota", "api_recharge", 1_000_000, "completed"),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    4: ("scheduled", "manual_purchase", 700_000, "completed"),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    5: ("scheduled", "api_recharge", 900_000, "pending"),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    6: ("manual", "manual_purchase", 600_000, "in_progress"),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    7: ("scheduled", "manual_purchase", 500_000, "failed"),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    8: ("low_quota", "api_recharge", 1_200_000, "failed"),  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
}

restock_tasks: list[dict[str, Any]] = []  # 作用：计算或保存右侧结果，供后续步骤继续使用
completed_restock: dict[int, int] = defaultdict(int)  # 作用：计算或保存右侧结果，供后续步骤继续使用
for account_id in range(1, 9):  # 作用：遍历当前集合，逐项生成、统计或校验数据
    trigger, method, target, status = task_plan[account_id]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    actual = target if status == "completed" else None  # 作用：计算或保存右侧结果，供后续步骤继续使用
    created_at = datetime(2026, 9, 18, 9, 0, 0) + timedelta(hours=account_id)  # 作用：计算或保存右侧结果，供后续步骤继续使用
    completed_at = created_at + timedelta(minutes=30) if status == "completed" else None  # 作用：计算或保存右侧结果，供后续步骤继续使用
    if actual is not None:  # 作用：检查当前条件是否成立，成立时进入对应分支
        completed_restock[account_id] += actual  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    restock_tasks.append(  # 作用：把当前生成的一条记录追加到目标列表
        {
            "task_id": account_id,  # 作用：定义当前记录的一个字段及其对应值
            "account_id": account_id,  # 作用：定义当前记录的一个字段及其对应值
            "trigger_reason": trigger,  # 作用：定义当前记录的一个字段及其对应值
            "restock_method": method,  # 作用：定义当前记录的一个字段及其对应值
            "target_amount": target,  # 作用：定义当前记录的一个字段及其对应值
            "actual_amount": actual,  # 作用：定义当前记录的一个字段及其对应值
            "created_by": 1,  # 作用：定义当前记录的一个字段及其对应值
            "assigned_to": 3 if status in {"completed", "in_progress"} else None,  # 作用：定义当前记录的一个字段及其对应值
            "status": status,  # 作用：定义当前记录的一个字段及其对应值
            "created_at": created_at,  # 作用：定义当前记录的一个字段及其对应值
            "completed_at": completed_at,  # 作用：定义当前记录的一个字段及其对应值
            "notes": f"教学合成补货任务 #{account_id}",  # 作用：定义当前记录的一个字段及其对应值
        }
    )

accounts: list[dict[str, Any]] = []  # 作用：计算或保存右侧结果，供后续步骤继续使用
inventory: list[dict[str, Any]] = []  # 作用：计算或保存右侧结果，供后续步骤继续使用
initial_purchase_by_account: dict[int, int] = {}  # 作用：计算或保存右侧结果，供后续步骤继续使用
for account_id, provider, account_name, status in ACCOUNT_SPECS:  # 作用：遍历当前集合，逐项生成、统计或校验数据
    consumed = consumed_by_account[account_id]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    initial_purchase = consumed + reserve_by_account[account_id]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    if initial_purchase <= 0:  # 作用：检查当前条件是否成立，成立时进入对应分支
        initial_purchase = 100_000  # 作用：计算或保存右侧结果，供后续步骤继续使用
    initial_purchase_by_account[account_id] = initial_purchase  # 作用：计算或保存右侧结果，供后续步骤继续使用
    total_quota = initial_purchase + completed_restock[account_id]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    current_quota = total_quota - consumed  # 作用：计算或保存右侧结果，供后续步骤继续使用
    expires_at = (  # 作用：计算或保存右侧结果，供后续步骤继续使用
        datetime(2026, 8, 31, 23, 59, 59)  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        if status == "expired"  # 作用：检查当前条件是否成立，成立时进入对应分支
        else datetime(2027, 12, 31, 23, 59, 59)  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    )
    accounts.append(  # 作用：把当前生成的一条记录追加到目标列表
        {
            "account_id": account_id,  # 作用：定义当前记录的一个字段及其对应值
            "provider": provider,  # 作用：定义当前记录的一个字段及其对应值
            "account_name": account_name,  # 作用：定义当前记录的一个字段及其对应值
            "api_key": f"DEMO_NOT_A_REAL_API_KEY_{account_id:02d}",  # 作用：定义当前记录的一个字段及其对应值
            "total_quota": total_quota,  # 作用：定义当前记录的一个字段及其对应值
            "used_quota": consumed,  # 作用：定义当前记录的一个字段及其对应值
            "safety_threshold": 500_000,  # 作用：定义当前记录的一个字段及其对应值
            "status": status,  # 作用：定义当前记录的一个字段及其对应值
            "expires_at": expires_at,  # 作用：定义当前记录的一个字段及其对应值
            "created_at": datetime(2026, 6, 20, 8, 0, 0),  # 作用：定义当前记录的一个字段及其对应值
            "updated_at": END,  # 作用：定义当前记录的一个字段及其对应值
        }
    )
    inventory.append(  # 作用：把当前生成的一条记录追加到目标列表
        {
            "inventory_id": account_id,  # 作用：定义当前记录的一个字段及其对应值
            "account_id": account_id,  # 作用：定义当前记录的一个字段及其对应值
            "current_quota": current_quota,  # 作用：定义当前记录的一个字段及其对应值
            "last_updated_at": END,  # 作用：定义当前记录的一个字段及其对应值
        }
    )

inventory_logs: list[dict[str, Any]] = []  # 作用：计算或保存右侧结果，供后续步骤继续使用
inventory_log_id = 1  # 作用：计算或保存右侧结果，供后续步骤继续使用
for account_id in range(1, 9):  # 作用：遍历当前集合，逐项生成、统计或校验数据
    inventory_logs.append(  # 作用：把当前生成的一条记录追加到目标列表
        {
            "log_id": inventory_log_id,  # 作用：定义当前记录的一个字段及其对应值
            "account_id": account_id,  # 作用：定义当前记录的一个字段及其对应值
            "change_type": "purchase",  # 作用：定义当前记录的一个字段及其对应值
            "change_amount": initial_purchase_by_account[account_id],  # 作用：定义当前记录的一个字段及其对应值
            "reference_id": None,  # 作用：定义当前记录的一个字段及其对应值
            "reference_type": None,  # 作用：定义当前记录的一个字段及其对应值
            "reason": "期初采购额度",  # 作用：定义当前记录的一个字段及其对应值
            "operator_id": 3,  # 作用：定义当前记录的一个字段及其对应值
            "created_at": datetime(2026, 6, 30, 12, 0, 0),  # 作用：定义当前记录的一个字段及其对应值
        }
    )
    inventory_log_id += 1  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑

for usage in usage_logs:  # 作用：遍历当前集合，逐项生成、统计或校验数据
    inventory_logs.append(  # 作用：把当前生成的一条记录追加到目标列表
        {
            "log_id": inventory_log_id,  # 作用：定义当前记录的一个字段及其对应值
            "account_id": usage["account_id"],  # 作用：定义当前记录的一个字段及其对应值
            "change_type": "consumption",  # 作用：定义当前记录的一个字段及其对应值
            "change_amount": -usage["upstream_tokens_consumed"],  # 作用：定义当前记录的一个字段及其对应值
            "reference_id": usage["log_id"],  # 作用：定义当前记录的一个字段及其对应值
            "reference_type": "manual",  # 作用：定义当前记录的一个字段及其对应值
            "reason": f"API 调用消耗，对应 usage_log#{usage['log_id']}",  # 作用：定义当前记录的一个字段及其对应值
            "operator_id": None,  # 作用：定义当前记录的一个字段及其对应值
            "created_at": usage["used_at"],  # 作用：定义当前记录的一个字段及其对应值
        }
    )
    inventory_log_id += 1  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑

for task in restock_tasks:  # 作用：遍历当前集合，逐项生成、统计或校验数据
    if task["status"] == "completed":  # 作用：检查当前条件是否成立，成立时进入对应分支
        inventory_logs.append(  # 作用：把当前生成的一条记录追加到目标列表
            {
                "log_id": inventory_log_id,  # 作用：定义当前记录的一个字段及其对应值
                "account_id": task["account_id"],  # 作用：定义当前记录的一个字段及其对应值
                "change_type": "restock",  # 作用：定义当前记录的一个字段及其对应值
                "change_amount": task["actual_amount"],  # 作用：定义当前记录的一个字段及其对应值
                "reference_id": task["task_id"],  # 作用：定义当前记录的一个字段及其对应值
                "reference_type": "restock_task",  # 作用：定义当前记录的一个字段及其对应值
                "reason": f"补货任务 #{task['task_id']} 完成",  # 作用：定义当前记录的一个字段及其对应值
                "operator_id": 3,  # 作用：定义当前记录的一个字段及其对应值
                "created_at": task["completed_at"],  # 作用：定义当前记录的一个字段及其对应值
            }
        )
        inventory_log_id += 1  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑

token_balances: list[dict[str, Any]] = []  # 作用：计算或保存右侧结果，供后续步骤继续使用
for balance_id, ((user_id, provider), remaining) in enumerate(  # 作用：遍历当前集合，逐项生成、统计或校验数据
    sorted(credits.items()), start=1  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
):
    token_balances.append(  # 作用：把当前生成的一条记录追加到目标列表
        {
            "balance_id": balance_id,  # 作用：定义当前记录的一个字段及其对应值
            "user_id": user_id,  # 作用：定义当前记录的一个字段及其对应值
            "model_provider": provider,  # 作用：定义当前记录的一个字段及其对应值
            "remaining_tokens": remaining,  # 作用：定义当前记录的一个字段及其对应值
            "updated_at": END,  # 作用：定义当前记录的一个字段及其对应值
        }
    )

summary_acc: dict[tuple[int, int, str, date, date], list[int]] = defaultdict(  # 作用：计算或保存右侧结果，供后续步骤继续使用
    lambda: [0, 0, 0]  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
)
for row in usage_logs:  # 作用：遍历当前集合，逐项生成、统计或校验数据
    used_date = row["used_at"].date()  # 作用：计算或保存右侧结果，供后续步骤继续使用
    week_start = used_date - timedelta(days=used_date.weekday())  # 作用：计算或保存右侧结果，供后续步骤继续使用
    week_end = week_start + timedelta(days=6)  # 作用：计算或保存右侧结果，供后续步骤继续使用
    month_start = used_date.replace(day=1)  # 作用：计算或保存右侧结果，供后续步骤继续使用
    if month_start.month == 12:  # 作用：检查当前条件是否成立，成立时进入对应分支
        next_month = date(month_start.year + 1, 1, 1)  # 作用：计算或保存右侧结果，供后续步骤继续使用
    else:  # 作用：处理前面条件都不成立时的剩余情况
        next_month = date(month_start.year, month_start.month + 1, 1)  # 作用：计算或保存右侧结果，供后续步骤继续使用
    month_end = next_month - timedelta(days=1)  # 作用：计算或保存右侧结果，供后续步骤继续使用

    periods = [  # 作用：计算或保存右侧结果，供后续步骤继续使用
        ("daily", used_date, used_date),
        ("weekly", week_start, week_end),
        ("monthly", month_start, month_end),
    ]
    for period_type, period_start, period_end in periods:  # 作用：遍历当前集合，逐项生成、统计或校验数据
        key = (  # 作用：计算或保存右侧结果，供后续步骤继续使用
            row["user_id"],  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            row["product_id"],  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            period_type,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            period_start,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            period_end,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        )
        acc = summary_acc[key]  # 作用：计算或保存右侧结果，供后续步骤继续使用
        acc[0] += row["tokens_used"]  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        acc[1] += row["upstream_tokens_consumed"]  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        acc[2] += 1  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑

usage_summary: list[dict[str, Any]] = []  # 作用：计算或保存右侧结果，供后续步骤继续使用
for summary_id, (key, values) in enumerate(sorted(summary_acc.items()), start=1):  # 作用：遍历当前集合，逐项生成、统计或校验数据
    user_id, product_id, period_type, period_start, period_end = key  # 作用：计算或保存右侧结果，供后续步骤继续使用
    last_date = min(period_end, END.date())  # 作用：计算或保存右侧结果，供后续步骤继续使用
    usage_summary.append(  # 作用：把当前生成的一条记录追加到目标列表
        {
            "summary_id": summary_id,  # 作用：定义当前记录的一个字段及其对应值
            "user_id": user_id,  # 作用：定义当前记录的一个字段及其对应值
            "product_id": product_id,  # 作用：定义当前记录的一个字段及其对应值
            "period_type": period_type,  # 作用：定义当前记录的一个字段及其对应值
            "period_start": period_start,  # 作用：定义当前记录的一个字段及其对应值
            "period_end": period_end,  # 作用：定义当前记录的一个字段及其对应值
            "total_tokens_used": values[0],  # 作用：定义当前记录的一个字段及其对应值
            "total_upstream_consumed": values[1],  # 作用：定义当前记录的一个字段及其对应值
            "request_count": values[2],  # 作用：定义当前记录的一个字段及其对应值
            "last_updated_at": datetime.combine(  # 作用：定义当前记录的一个字段及其对应值
                last_date, datetime.max.time()  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            ).replace(microsecond=0),
        }
    )

exception_logs: list[dict[str, Any]] = []  # 作用：计算或保存右侧结果，供后续步骤继续使用
exception_types = ["api_error", "inventory_error", "payment_error", "system_error"]  # 作用：计算或保存右侧结果，供后续步骤继续使用
for exception_id in range(1, 16):  # 作用：遍历当前集合，逐项生成、统计或校验数据
    kind = exception_types[(exception_id - 1) % len(exception_types)]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    sample_usage = rng.choice(usage_logs)  # 作用：计算或保存右侧结果，供后续步骤继续使用
    if kind == "api_error":  # 作用：检查当前条件是否成立，成立时进入对应分支
        related_table = "TokenUsageLogs"  # 作用：计算或保存右侧结果，供后续步骤继续使用
        related_id = sample_usage["log_id"]  # 作用：计算或保存右侧结果，供后续步骤继续使用
        message = "API 调用失败：模拟速率限制"  # 作用：计算或保存右侧结果，供后续步骤继续使用
        detail = "教学数据：用于演示异常记录与后续处理"  # 作用：计算或保存右侧结果，供后续步骤继续使用
    elif kind == "inventory_error":  # 作用：继续判断前面未命中的另一种情况
        related_table = "Inventory"  # 作用：计算或保存右侧结果，供后续步骤继续使用
        related_id = sample_usage["account_id"]  # 作用：计算或保存右侧结果，供后续步骤继续使用
        message = "库存检查异常：模拟额度接近阈值"  # 作用：计算或保存右侧结果，供后续步骤继续使用
        detail = "教学数据：触发人工复核"  # 作用：计算或保存右侧结果，供后续步骤继续使用
    elif kind == "payment_error":  # 作用：继续判断前面未命中的另一种情况
        related_table = "Orders"  # 作用：计算或保存右侧结果，供后续步骤继续使用
        related_id = rng.randint(1, 100)  # 作用：计算或保存右侧结果，供后续步骤继续使用
        message = "支付回调异常：模拟状态同步失败"  # 作用：计算或保存右侧结果，供后续步骤继续使用
        detail = "教学数据：订单状态需重新核对"  # 作用：计算或保存右侧结果，供后续步骤继续使用
    else:  # 作用：处理前面条件都不成立时的剩余情况
        related_table = None  # 作用：计算或保存右侧结果，供后续步骤继续使用
        related_id = None  # 作用：计算或保存右侧结果，供后续步骤继续使用
        message = "系统异常：模拟后台任务超时"  # 作用：计算或保存右侧结果，供后续步骤继续使用
        detail = "教学数据：用于异常分类统计"  # 作用：计算或保存右侧结果，供后续步骤继续使用

    result = rng.choice(["resolved", "ignored", "escalated"])  # 作用：计算或保存右侧结果，供后续步骤继续使用
    occurred_at = sample_usage["used_at"] + timedelta(minutes=rng.randint(1, 15))  # 作用：计算或保存右侧结果，供后续步骤继续使用
    handled_by = rng.randint(2, 5)  # 作用：计算或保存右侧结果，供后续步骤继续使用
    exception_logs.append(  # 作用：把当前生成的一条记录追加到目标列表
        {
            "exception_id": exception_id,  # 作用：定义当前记录的一个字段及其对应值
            "exception_type": kind,  # 作用：定义当前记录的一个字段及其对应值
            "related_table": related_table,  # 作用：定义当前记录的一个字段及其对应值
            "related_id": related_id,  # 作用：定义当前记录的一个字段及其对应值
            "error_message": message,  # 作用：定义当前记录的一个字段及其对应值
            "error_detail": detail,  # 作用：定义当前记录的一个字段及其对应值
            "occurred_at": occurred_at,  # 作用：定义当前记录的一个字段及其对应值
            "handled_by": handled_by,  # 作用：定义当前记录的一个字段及其对应值
            "handle_result": result,  # 作用：定义当前记录的一个字段及其对应值
            "handle_notes": "已按教学流程记录处理结果",  # 作用：定义当前记录的一个字段及其对应值
            "handled_at": occurred_at + timedelta(minutes=rng.randint(5, 90)),  # 作用：定义当前记录的一个字段及其对应值
        }
    )



def self_check() -> None:  # 作用：定义 self_check 函数，封装这一段可重复调用的逻辑
    detail_by_order: dict[int, list[dict[str, Any]]] = defaultdict(list)  # 作用：计算或保存右侧结果，供后续步骤继续使用
    for row in order_details:  # 作用：遍历当前集合，逐项生成、统计或校验数据
        detail_by_order[row["order_id"]].append(row)  # 作用：把当前生成的一条记录追加到目标列表

    for order in orders:  # 作用：遍历当前集合，逐项生成、统计或校验数据
        rows = detail_by_order[order["order_id"]]  # 作用：计算或保存右侧结果，供后续步骤继续使用
        assert sum((r["subtotal"] for r in rows), Decimal("0.00")) == order["total_amount"]  # 作用：执行一致性断言，不满足条件时立即暴露生成错误
        assert sum(r["total_tokens"] for r in rows) == order["total_tokens"]  # 作用：执行一致性断言，不满足条件时立即暴露生成错误

    assert all(row["remaining_tokens"] >= 0 for row in token_balances)  # 作用：执行一致性断言，不满足条件时立即暴露生成错误
    assert len(usage_logs) == 3000  # 作用：执行一致性断言，不满足条件时立即暴露生成错误

    user_set = {row["user_id"] for row in users}  # 作用：计算或保存右侧结果，供后续步骤继续使用
    product_set = {row["product_id"] for row in products}  # 作用：计算或保存右侧结果，供后续步骤继续使用
    account_set = {row["account_id"] for row in accounts}  # 作用：计算或保存右侧结果，供后续步骤继续使用
    employee_set = {row["employee_id"] for row in employees}  # 作用：计算或保存右侧结果，供后续步骤继续使用
    order_set = {row["order_id"] for row in orders}  # 作用：计算或保存右侧结果，供后续步骤继续使用

    for row in order_details:  # 作用：遍历当前集合，逐项生成、统计或校验数据
        assert row["order_id"] in order_set  # 作用：执行一致性断言，不满足条件时立即暴露生成错误
        assert row["product_id"] in product_set  # 作用：执行一致性断言，不满足条件时立即暴露生成错误
    for row in usage_logs:  # 作用：遍历当前集合，逐项生成、统计或校验数据
        assert row["user_id"] in user_set  # 作用：执行一致性断言，不满足条件时立即暴露生成错误
        assert row["product_id"] in product_set  # 作用：执行一致性断言，不满足条件时立即暴露生成错误
        assert row["account_id"] in account_set  # 作用：执行一致性断言，不满足条件时立即暴露生成错误
        assert PRODUCT_BY_ID[row["product_id"]].provider == next(  # 作用：执行一致性断言，不满足条件时立即暴露生成错误
            a["provider"] for a in accounts if a["account_id"] == row["account_id"]  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        )
    for row in inventory_logs:  # 作用：遍历当前集合，逐项生成、统计或校验数据
        assert row["account_id"] in account_set  # 作用：执行一致性断言，不满足条件时立即暴露生成错误
        assert row["operator_id"] is None or row["operator_id"] in employee_set  # 作用：执行一致性断言，不满足条件时立即暴露生成错误

    log_sum: dict[int, int] = defaultdict(int)  # 作用：计算或保存右侧结果，供后续步骤继续使用
    for row in inventory_logs:  # 作用：遍历当前集合，逐项生成、统计或校验数据
        log_sum[row["account_id"]] += row["change_amount"]  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    inventory_by_account = {row["account_id"]: row for row in inventory}  # 作用：计算或保存右侧结果，供后续步骤继续使用
    for account in accounts:  # 作用：遍历当前集合，逐项生成、统计或校验数据
        account_id = account["account_id"]  # 作用：计算或保存右侧结果，供后续步骤继续使用
        expected = account["total_quota"] - account["used_quota"]  # 作用：计算或保存右侧结果，供后续步骤继续使用
        assert inventory_by_account[account_id]["current_quota"] == expected  # 作用：执行一致性断言，不满足条件时立即暴露生成错误
        assert log_sum[account_id] == expected  # 作用：执行一致性断言，不满足条件时立即暴露生成错误

    assert all(str(row["api_key"]).startswith("DEMO_NOT_A_REAL") for row in accounts)  # 作用：执行一致性断言，不满足条件时立即暴露生成错误
    assert all(len(row["password_hash"]) == 60 for row in users)  # 作用：执行一致性断言，不满足条件时立即暴露生成错误
    assert all(len(row["password_hash"]) == 60 for row in employees)  # 作用：执行一致性断言，不满足条件时立即暴露生成错误


def sql_value(value: Any) -> str:  # 作用：定义 sql_value 函数，封装这一段可重复调用的逻辑
    if value is None:  # 作用：检查当前条件是否成立，成立时进入对应分支
        return "NULL"  # 作用：把当前函数的计算结果返回给调用者
    if isinstance(value, bool):  # 作用：检查当前条件是否成立，成立时进入对应分支
        return "1" if value else "0"  # 作用：把当前函数的计算结果返回给调用者
    if isinstance(value, Decimal):  # 作用：检查当前条件是否成立，成立时进入对应分支
        return format(value, "f")  # 作用：把当前函数的计算结果返回给调用者
    if isinstance(value, datetime):  # 作用：检查当前条件是否成立，成立时进入对应分支
        return "'" + value.strftime("%Y-%m-%d %H:%M:%S") + "'"  # 作用：把当前函数的计算结果返回给调用者
    if isinstance(value, date):  # 作用：检查当前条件是否成立，成立时进入对应分支
        return "'" + value.strftime("%Y-%m-%d") + "'"  # 作用：把当前函数的计算结果返回给调用者
    if isinstance(value, int):  # 作用：检查当前条件是否成立，成立时进入对应分支
        return str(value)  # 作用：把当前函数的计算结果返回给调用者
    text = str(value).replace("'", "''")  # 作用：计算或保存右侧结果，供后续步骤继续使用
    return "N'" + text + "'"  # 作用：把当前函数的计算结果返回给调用者


def emit_identity(  # 作用：定义 emit_identity 函数，封装这一段可重复调用的逻辑
    table: str,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    columns: list[str],  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    rows: Iterable[dict[str, Any]],  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    batch_size: int = 500,  # 作用：计算或保存右侧结果，供后续步骤继续使用
) -> list[str]:
    materialized = list(rows)  # 作用：计算或保存右侧结果，供后续步骤继续使用
    lines = [f"SET IDENTITY_INSERT dbo.{table} ON;", "GO"]  # 作用：计算或保存右侧结果，供后续步骤继续使用
    for start in range(0, len(materialized), batch_size):  # 作用：遍历当前集合，逐项生成、统计或校验数据
        batch = materialized[start : start + batch_size]  # 作用：计算或保存右侧结果，供后续步骤继续使用
        lines.append(f"INSERT INTO dbo.{table} ({', '.join(columns)}) VALUES")  # 作用：把当前生成的一条记录追加到目标列表
        rendered = []  # 作用：计算或保存右侧结果，供后续步骤继续使用
        for row in batch:  # 作用：遍历当前集合，逐项生成、统计或校验数据
            rendered.append(  # 作用：把当前生成的一条记录追加到目标列表
                "    (" + ", ".join(sql_value(row[column]) for column in columns) + ")"  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            )
        lines.append(",\n".join(rendered) + ";")  # 作用：把当前生成的一条记录追加到目标列表
        lines.append("GO")  # 作用：把当前生成的一条记录追加到目标列表
    lines.extend([f"SET IDENTITY_INSERT dbo.{table} OFF;", "GO", ""])  # 作用：把一批生成结果追加到目标列表
    return lines  # 作用：把当前函数的计算结果返回给调用者


def build_sql() -> str:  # 作用：定义 build_sql 函数，封装这一段可重复调用的逻辑
    sections: list[str] = [  # 作用：计算或保存右侧结果，供后续步骤继续使用
        "-- Generated by tools/datagen.py",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        f"-- Fixed seed: {SEED}",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        "-- All credentials are non-secret teaching placeholders.",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        "-- Pricing direction was checked against provider API pricing on 2026-09-23;",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        "-- retail package prices are simplified for this database experiment.",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        "",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        "USE [TokenHubDB_Week3];",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        "GO",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        "SET NOCOUNT ON;",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        "SET XACT_ABORT ON;",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        "BEGIN TRANSACTION;",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        "GO",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        "",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    ]

    table_specs = [  # 作用：计算或保存右侧结果，供后续步骤继续使用
        ("Roles", ["role_id", "role_name", "description", "permissions"], roles),
        (
            "Users",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            ["user_id", "username", "password_hash", "email", "phone", "status", "created_at", "updated_at"],
            users,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        ),
        (
            "Products",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            ["product_id", "name", "description", "price", "model_provider", "token_amount", "required_upstream_tokens", "status", "created_at"],
            products,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        ),
        (
            "UpstreamAccount",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            ["account_id", "provider", "account_name", "api_key", "total_quota", "used_quota", "safety_threshold", "status", "expires_at", "created_at", "updated_at"],
            accounts,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        ),
        ("Inventory", ["inventory_id", "account_id", "current_quota", "last_updated_at"], inventory),
        (
            "Employees",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            ["employee_id", "name", "role_id", "account", "password_hash", "hire_date", "status"],
            employees,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        ),
        (
            "Orders",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            ["order_id", "user_id", "total_amount", "total_tokens", "status", "created_at", "paid_at"],
            orders,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        ),
        (
            "OrderDetails",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            ["detail_id", "order_id", "product_id", "quantity", "unit_price", "subtotal", "tokens_per_unit", "total_tokens"],
            order_details,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        ),
        (
            "InventoryLog",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            ["log_id", "account_id", "change_type", "change_amount", "reference_id", "reference_type", "reason", "operator_id", "created_at"],
            inventory_logs,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        ),
        (
            "TokenBalances",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            ["balance_id", "user_id", "model_provider", "remaining_tokens", "updated_at"],
            token_balances,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        ),
        (
            "TokenUsageLogs",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            ["log_id", "user_id", "product_id", "account_id", "tokens_used", "upstream_tokens_consumed", "api_endpoint", "used_at"],
            usage_logs,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        ),
        (
            "UsageSummary",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            ["summary_id", "user_id", "product_id", "period_type", "period_start", "period_end", "total_tokens_used", "total_upstream_consumed", "request_count", "last_updated_at"],
            usage_summary,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        ),
        (
            "RestockTask",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            ["task_id", "account_id", "trigger_reason", "restock_method", "target_amount", "actual_amount", "created_by", "assigned_to", "status", "created_at", "completed_at", "notes"],
            restock_tasks,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        ),
        (
            "ExceptionLog",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            ["exception_id", "exception_type", "related_table", "related_id", "error_message", "error_detail", "occurred_at", "handled_by", "handle_result", "handle_notes", "handled_at"],
            exception_logs,  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        ),
    ]

    for table, columns, rows in table_specs:  # 作用：遍历当前集合，逐项生成、统计或校验数据
        sections.extend(emit_identity(table, columns, rows))  # 作用：把一批生成结果追加到目标列表

    sections.extend(  # 作用：把一批生成结果追加到目标列表
        [
            "COMMIT TRANSACTION;",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            "GO",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            "",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            "SELECT N'Data load completed' AS message;",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
            "GO",  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
        ]
    )
    return "\n".join(sections)  # 作用：把当前函数的计算结果返回给调用者


def main() -> None:  # 作用：定义 main 函数，封装这一段可重复调用的逻辑
    self_check()  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
    sql_text = build_sql()  # 作用：计算或保存右侧结果，供后续步骤继续使用
    OUT_PATH.write_text(sql_text, encoding="utf-8")  # 作用：把最终 SQL 文本以 UTF-8 编码写入目标文件
    counts = {  # 作用：计算或保存右侧结果，供后续步骤继续使用
        "Users": len(users),  # 作用：定义当前记录的一个字段及其对应值
        "Products": len(products),  # 作用：定义当前记录的一个字段及其对应值
        "UpstreamAccount": len(accounts),  # 作用：定义当前记录的一个字段及其对应值
        "Inventory": len(inventory),  # 作用：定义当前记录的一个字段及其对应值
        "Employees": len(employees),  # 作用：定义当前记录的一个字段及其对应值
        "Orders": len(orders),  # 作用：定义当前记录的一个字段及其对应值
        "OrderDetails": len(order_details),  # 作用：定义当前记录的一个字段及其对应值
        "InventoryLog": len(inventory_logs),  # 作用：定义当前记录的一个字段及其对应值
        "TokenBalances": len(token_balances),  # 作用：定义当前记录的一个字段及其对应值
        "TokenUsageLogs": len(usage_logs),  # 作用：定义当前记录的一个字段及其对应值
        "UsageSummary": len(usage_summary),  # 作用：定义当前记录的一个字段及其对应值
        "RestockTask": len(restock_tasks),  # 作用：定义当前记录的一个字段及其对应值
        "ExceptionLog": len(exception_logs),  # 作用：定义当前记录的一个字段及其对应值
    }
    print(f"seed={SEED}")  # 作用：打印当前生成或验证结果，便于人工核对
    print(f"output={OUT_PATH}")  # 作用：打印当前生成或验证结果，便于人工核对
    for table, count in counts.items():  # 作用：遍历当前集合，逐项生成、统计或校验数据
        print(f"{table}={count}")  # 作用：打印当前生成或验证结果，便于人工核对
    print("self_check=PASS")  # 作用：打印当前生成或验证结果，便于人工核对


if __name__ == "__main__":  # 作用：只在直接运行本文件时调用 main，导入模块时不会自动执行
    main()  # 作用：执行当前步骤，完成这一段数据生成或 SQL 输出逻辑
