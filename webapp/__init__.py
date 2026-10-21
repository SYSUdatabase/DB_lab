"""Application factory, safe error boundary and resource-oriented HTTP routes."""

from __future__ import annotations

import logging
import os
import secrets
import uuid
from collections.abc import Callable
from logging.handlers import RotatingFileHandler
from pathlib import Path

from flask import Flask, Response, g, jsonify, render_template, request, session
from werkzeug.exceptions import HTTPException

from . import dao, services
from .errors import AppError


def create_app(overrides: dict[str, object] | None = None) -> Flask:
    app = Flask(__name__, instance_relative_config=True)
    app.config.from_mapping(
        SECRET_KEY=os.environ.get("DB_LAB_SECRET"),
        DB_SERVER=os.environ.get("DB_LAB_SERVER", r"localhost\SQLEXPRESS"),
        DB_DATABASE=os.environ.get("DB_LAB_APP_DATABASE", ""),
        DB_PREVIEW=os.environ.get("DB_LAB_PREVIEW") == "1",
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Strict",
        SESSION_COOKIE_SECURE=os.environ.get("DB_LAB_HTTPS") == "1",
        MAX_CONTENT_LENGTH=65536,
    )
    if overrides:
        app.config.update(overrides)
    if not app.config["SECRET_KEY"]:
        raise RuntimeError("Set DB_LAB_SECRET before starting the application")
    Path(app.instance_path).mkdir(exist_ok=True, parents=True)
    handler = RotatingFileHandler(
        Path(app.instance_path) / "webapp.log", maxBytes=2_000_000, backupCount=3, encoding="utf-8"
    )
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    app.logger.addHandler(handler)
    app.logger.setLevel(logging.INFO)
    install_boundaries(app)
    install_routes(app)
    return app


def install_boundaries(app: Flask) -> None:
    @app.before_request
    def before() -> None:
        g.request_id = uuid.uuid4().hex
        g.role, g.operation = "guest", request.endpoint or "unknown"
        if request.method in {"POST", "PUT", "PATCH", "DELETE"} and request.endpoint:
            expected = session.get("csrf")
            supplied = request.headers.get("X-CSRF-Token", "")
            if not expected or not secrets.compare_digest(str(expected), supplied):
                raise AppError("CSRF_REJECTED", "页面已失效，请刷新后重试", 403)

    @app.after_request
    def after(response: Response) -> Response:
        response.headers.update(
            {
                "X-Request-ID": g.request_id,
                "X-Content-Type-Options": "nosniff",
                "X-Frame-Options": "DENY",
                "Referrer-Policy": "same-origin",
                "Cache-Control": "no-store",
                "Content-Security-Policy": "default-src 'self'; script-src 'self'; "
                "style-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'self'",
            }
        )
        app.logger.info(
            "request_id=%s operation=%s role=%s code=%s result=%s",
            g.request_id,
            g.operation,
            g.role,
            getattr(g, "error_code", "OK"),
            response.status_code,
        )
        return response

    @app.errorhandler(Exception)
    def error_boundary(error: Exception) -> tuple[Response, int]:
        if isinstance(error, AppError):
            safe = error
        elif isinstance(error, HTTPException):
            status = error.code or 500
            safe = AppError(
                "NOT_FOUND" if status == 404 else "INVALID_REQUEST",
                "请求地址不存在" if status == 404 else "请求格式不正确",
                status,
            )
        else:
            safe = AppError("INTERNAL_ERROR", "系统暂时无法完成操作，请提供请求编号", 500)
            app.logger.error(
                "unexpected request_id=%s exception_type=%s", g.request_id, type(error).__name__
            )
        g.error_code = safe.code
        return jsonify(
            code=safe.code, message=safe.message, data=None, request_id=g.request_id
        ), safe.status


ROUTES = (
    ("/products", "GET", "products.list"),
    ("/products", "POST", "products.save"),
    ("/products/<int:product_id>", "PUT", "products.save"),
    ("/products/<int:product_id>", "DELETE", "products.delete"),
    ("/orders", "GET", "orders.list"),
    ("/orders", "POST", "orders.create"),
    ("/orders/<int:order_id>", "GET", "orders.get"),
    ("/orders/<int:order_id>", "DELETE", "orders.delete"),
    ("/orders/<int:order_id>/items", "POST", "orders.item_add"),
    ("/orders/<int:order_id>/items/<int:detail_id>", "PUT", "orders.item_set"),
    ("/orders/<int:order_id>/items/<int:detail_id>", "DELETE", "orders.item_delete"),
    ("/orders/<int:order_id>/pay", "POST", "orders.pay"),
    ("/orders/<int:order_id>/cancel", "POST", "orders.cancel"),
    ("/usage", "GET", "usage.list"),
    ("/usage", "POST", "usage.create"),
    ("/balances", "GET", "balances.list"),
    ("/inventory", "GET", "inventory.list"),
    ("/accounts", "POST", "accounts.save"),
    ("/accounts/<int:account_id>", "PUT", "accounts.save"),
    ("/accounts/<int:account_id>", "DELETE", "accounts.delete"),
    ("/restocks", "GET", "restocks.list"),
    ("/restocks", "POST", "restocks.create"),
    ("/restocks/<int:task_id>/complete", "POST", "restocks.complete"),
    ("/refunds", "GET", "refunds.list"),
    ("/orders/<int:order_id>/refund", "POST", "refunds.request"),
    ("/orders/<int:order_id>/settle", "POST", "refunds.settle"),
)


def success(data: object) -> Response:
    return jsonify(code="OK", message="操作成功", data=data, request_id=g.request_id)


def json_body() -> dict[str, object]:
    data = request.get_json()
    if not isinstance(data, dict):
        raise AppError("INVALID_INPUT", "请求内容应为对象", 400)
    return data


def operation_view(operation: str) -> Callable[..., Response]:
    def view(**identifiers: int) -> Response:
        g.operation = operation
        token = session.get("token")
        principal = services.identity(token)
        g.role = principal["role"]
        payload = request.args.to_dict() if request.method == "GET" else json_body()
        if any(
            key in payload and str(payload[key]) != str(value) for key, value in identifiers.items()
        ):
            raise AppError("INVALID_INPUT", "请求编号不一致", 400)
        payload.update(identifiers)
        return success(services.perform(operation, payload, token))

    return view


def install_routes(app: Flask) -> None:
    @app.get("/")
    def index() -> str:
        session.setdefault("csrf", secrets.token_urlsafe(32))
        return render_template("index.html", csrf=session["csrf"])

    @app.get("/api/v1/auth/session")
    def current_identity() -> Response:
        session.setdefault("csrf", secrets.token_urlsafe(32))
        return success({**services.identity(session.get("token")), "csrf": session["csrf"]})

    @app.post("/api/v1/auth/login")
    def login() -> Response:
        token, principal = services.login(json_body())
        session.clear()
        session.update(token=token, csrf=secrets.token_urlsafe(32))
        g.role = principal["role"]
        return success({**principal, "csrf": session["csrf"]})

    @app.post("/api/v1/auth/logout")
    def logout() -> Response:
        if session.get("token"):
            dao.authentication("end", services.digest(session["token"]))
        session.clear()
        return success({})

    for index, (path, method, operation) in enumerate(ROUTES):
        app.add_url_rule(
            "/api/v1" + path,
            endpoint=f"{operation}_{index}",
            view_func=operation_view(operation),
            methods=[method],
        )
