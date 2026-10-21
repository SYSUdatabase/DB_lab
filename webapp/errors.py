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
        55000: ("INVALID_INPUT", "请检查必填项、格式和数值范围", 400),
        55001: ("UNAUTHENTICATED", "请先登录，或重新登录后操作", 401),
        55003: ("FORBIDDEN", "当前身份没有此操作权限", 403),
        55004: ("NOT_FOUND", "记录不存在或不可访问", 404),
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
