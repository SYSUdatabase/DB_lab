"""Check order-form quantities in Edge with intercepted APIs and no database writes.

Requires the optional playwright package and a locally installed Microsoft Edge.
Run from the project root with .venv/Scripts/python.exe tools/check_order_quantity.py.
"""

from __future__ import annotations

import json
from pathlib import Path

from playwright.sync_api import Route, expect, sync_playwright

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    products = [
        {"product_id": 1, "name": "Quantity A", "price": "6.90", "status": "active"},
        {"product_id": 2, "name": "Quantity B", "price": "8.90", "status": "active"},
    ]
    submissions: list[dict[str, object]] = []
    html = (ROOT / "webapp/templates/index.html").read_text(encoding="utf-8")
    html = html.replace("{{ csrf }}", "quantity-check")
    for filename in ("app.js", "dashboard.js", "app.css"):
        html = html.replace(
            "{{ url_for('static',filename='" + filename + "') }}", "/static/" + filename
        )

    def respond(route: Route) -> None:
        path = route.request.url.removeprefix("http://quantity.test")
        if path == "/":
            route.fulfill(content_type="text/html; charset=utf-8", body=html)
            return
        if path.startswith("/static/"):
            route.fulfill(path=str(ROOT / "webapp" / path.lstrip("/")))
            return
        data: dict[str, object] = {"items": [], "total": 0}
        if path == "/api/v1/auth/session":
            data = {"role": "customer", "csrf": "quantity-check"}
        elif path.startswith("/api/v1/products"):
            data = {"items": products, "total": len(products)}
        elif path == "/api/v1/orders" and route.request.method == "POST":
            submissions.append(route.request.post_data_json)
            data = {"order_id": len(submissions)}
        route.fulfill(
            content_type="application/json",
            body=json.dumps({"code": "OK", "message": "", "data": data}),
        )

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="msedge", headless=True)
        page = browser.new_page()
        page.route("http://quantity.test/**", respond)

        def open_order(from_product: bool = True) -> None:
            page.goto("http://quantity.test/")
            expect(page.locator("#table-body tr")).to_have_count(2)
            if from_product:
                page.locator("#table-body tr").first.get_by_role("button", name="选购").click()
            else:
                page.get_by_role("button", name="创建订单", exact=True).click()
            expect(page.get_by_role("heading", name="创建订单", exact=True)).to_be_visible()

        def submit(expected: list[dict[str, object]]) -> None:
            page.get_by_role("button", name="提交订单", exact=True).click()
            expect(page.locator("#editor")).not_to_be_visible()
            assert submissions[-1]["items"] == expected, submissions[-1]

        open_order()
        page.get_by_label("数量", exact=True).fill("10")
        submit([{"product_id": 1, "quantity": "10"}])
        print("PASS product selection: quantity 10 is submitted as 10")

        open_order()
        submit([{"product_id": 1, "quantity": "1"}])
        print("PASS default quantity remains 1")

        open_order(from_product=False)
        page.get_by_label("选择套餐").select_option("1")
        page.get_by_label("数量", exact=True).fill("10")
        submit([{"product_id": 1, "quantity": "10"}])
        print("PASS create-order entry: quantity 10")

        open_order()
        page.get_by_label("数量", exact=True).fill("10")
        page.get_by_role("button", name="加入订单明细", exact=True).click()
        page.get_by_label("选择套餐").select_option("2")
        page.get_by_label("数量", exact=True).fill("3")
        page.get_by_role("button", name="加入订单明细", exact=True).click()
        submit([{"product_id": 1, "quantity": "10"}, {"product_id": 2, "quantity": "3"}])
        print("PASS explicit additions keep both product quantities without extra items")

        open_order()
        page.get_by_role("button", name="加入订单明细", exact=True).click()
        page.get_by_role("button", name="移除", exact=True).click()
        page.get_by_label("数量", exact=True).fill("4")
        submit([{"product_id": 1, "quantity": "4"}])
        print("PASS removed items are replaced by current form quantity")

        open_order()
        count = len(submissions)
        page.get_by_label("数量", exact=True).fill("2147483648")
        page.get_by_role("button", name="提交订单", exact=True).click()
        expect(page.locator("#editor .form-message")).to_contain_text("数量须为正整数")
        assert len(submissions) == count
        print("PASS out-of-range quantity creates no order")
        browser.close()


if __name__ == "__main__":
    main()
