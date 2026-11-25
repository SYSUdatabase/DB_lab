"""Safe HTTP errors and SQL error classification."""

from __future__ import annotations

import re


class AppError(Exception):
    def __init__(self, code: str, message: str, status: int) -> None:
        super().__init__(message)
        self.code, self.message, self.status = code, message, status


def database_error(error: Exception) -> AppError:
    detail = str(error)
    numbers = {int(n) for n in re.findall(r"\((\d{3,5})\)", detail)}
    mappings = {
        8115: ("INVALID_INPUT", "数量或金额超出数据库允许范围", 400),
        56000: ("INVALID_INPUT", "请检查日期、原因和数值范围", 400),
        56001: ("UNAUTHENTICATED", "请重新登录后操作", 401),
        56003: ("FORBIDDEN", "当前身份没有此操作权限", 403),
        56004: ("NOT_FOUND", "商品、账号或库存记录不存在", 404),
        56009: ("BUSINESS_CONFLICT", "库存状态或操作键发生冲突，请核对操作记录", 409),
        55000: ("INVALID_INPUT", "请检查必填项、格式和数值范围", 400),
        55001: ("UNAUTHENTICATED", "请先登录，或重新登录后操作", 401),
        55003: ("FORBIDDEN", "当前身份没有此操作权限", 403),
        55004: ("NOT_FOUND", "记录不存在或不可访问", 404),
        55010: ("INVENTORY_BUSY", "当前库存业务繁忙，请稍后重试", 409),
        55011: ("ORDER_NOT_PENDING", "订单不处于待支付状态，无法进行该操作", 409),
        53131: ("ORDER_ALREADY_PAID", "该订单已完成，请勿重复支付", 409),
        54401: ("ORDER_ALREADY_PAID", "该订单已完成，请勿重复支付", 409),
        53132: ("INSUFFICIENT_SELLABLE_QUOTA", "当前可售额度不足，请减少购买数量或稍后重试", 409),
        54406: ("INSUFFICIENT_SELLABLE_QUOTA", "当前可售额度不足，请减少购买数量或稍后重试", 409),
        53125: ("ORDER_EMPTY", "请先添加商品再支付", 409),
        54403: ("ORDER_EMPTY", "请先添加商品再支付", 409),
        53123: ("ORDER_NOT_PENDING", "订单不存在或不处于待支付状态", 409),
        54402: ("ORDER_NOT_PENDING", "订单不处于待支付状态，无法进行该操作", 409),
        53124: ("BUYER_UNAVAILABLE", "顾客账号当前不可完成订单", 409),
        53126: ("ORDER_ITEM_INVALID", "订单明细无效，请核对商品与数量", 409),
        54404: ("ORDER_ITEM_INVALID", "订单明细无效，请核对商品与数量", 409),
        53127: ("ORDER_TOTAL_MISMATCH", "订单金额或额度与明细不一致，请刷新核对", 409),
        54405: ("ORDER_TOTAL_MISMATCH", "订单金额或额度与明细不一致，请刷新核对", 409),
        53128: ("ORDER_NOT_PENDING", "订单状态已变化，请刷新核对", 409),
        53303: ("INVALID_INPUT", "补货数量必须大于零", 400),
        53305: ("RESTOCK_ACCOUNT_UNAVAILABLE", "上游账号或库存不可入库，请核对账号状态", 409),
        53306: ("RESTOCK_QUOTA_OVERFLOW", "补货数量超出额度允许范围，请减少数量", 409),
        53307: ("RESTOCK_INVENTORY_MISMATCH", "库存与账号额度不一致，请联系管理员核对", 409),
        53308: ("RESTOCK_CLOSED", "补货单状态已变化，请刷新核对", 409),
        53309: ("RESTOCK_INVENTORY_MISMATCH", "库存与账号额度不一致，请联系管理员核对", 409),
        53310: ("NOT_FOUND", "补货单不存在", 404),
        53311: ("RESTOCK_ALREADY_COMPLETED", "该补货单已入库，请勿重复操作", 409),
        53312: ("RESTOCK_CLOSED", "该补货单已关闭，无法入库", 409),
        53313: ("RESTOCK_PROVIDER_UNAVAILABLE", "该上游供应商尚无对应商品，无法入库", 409),
    }
    for number, values in mappings.items():
        if number in numbers:
            return AppError(*values)
    if numbers & {2601, 2627, 547}:
        return AppError("CONSTRAINT_CONFLICT", "记录重复或已被其他业务引用", 409)
    if numbers & {1205, 1222}:
        return AppError("TRANSACTION_CONFLICT", "操作发生冲突，请刷新并核对结果", 409)
    if any(50000 <= number <= 55999 for number in numbers):
        return AppError("BUSINESS_RULE", "当前状态、余额或可用额度不满足操作条件", 409)
    if detail.startswith("('08") or "HYT" in detail or isinstance(error, OSError):
        return AppError("DATABASE_UNAVAILABLE", "数据库暂时无法连接，请稍后再试", 503)
    return AppError("DATABASE_ERROR", "系统暂时无法完成操作，请提供请求编号", 500)
