"""Exercise Week 10 through live Edge pages and session-authorized HTTP calls."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import uuid
from pathlib import Path

from playwright.sync_api import Route, expect, sync_playwright


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:5052")
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    password = os.environ["DB_LAB_DEMO_PASSWORD"]
    args.evidence.mkdir(parents=True, exist_ok=False)
    events: list[dict[str, object]] = []
    pictures: list[dict[str, str]] = []
    tag = uuid.uuid4().hex[:10]
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="msedge", headless=True)
        page = browser.new_page(viewport={"width": 1440, "height": 1000})
        page.set_default_timeout(20000)

        def api(
            path: str,
            method: str = "GET",
            body: dict[str, object] | None = None,
            expected: int = 200,
        ) -> dict[str, object]:
            response = page.evaluate(
                """async ({path,method,body}) => {
                  const s=await (await fetch('/api/v1/auth/session')).json();
                  const opts={method,headers:{'Content-Type':'application/json','X-CSRF-Token':s.data.csrf}};
                  if(method!=='GET') opts.body=JSON.stringify(body||{});
                  const r=await fetch('/api/v1'+path,opts);
                  return {status:r.status,body:await r.json()};
                }""",
                {"path": path, "method": method, "body": body},
            )
            events.append(
                {
                    "path": path,
                    "method": method,
                    "status": response["status"],
                    "code": response["body"]["code"],
                    "request_id": response["body"]["request_id"],
                }
            )
            assert response["status"] == expected, response
            return response["body"]["data"]

        def shot(name: str) -> None:
            expect(page.locator("#feedback")).not_to_contain_text("正在读取")
            file = args.evidence / (name + ".png")
            page.screenshot(path=str(file), full_page=True, animations="disabled")
            pictures.append(
                {"file": file.name, "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
            )

        def login(account: str, kind: str = "employee") -> None:
            page.get_by_role("button", name="登录账户", exact=True).click()
            page.get_by_label("登录入口").select_option(kind)
            page.get_by_label("账号", exact=True).fill(account)
            page.get_by_label("密码", exact=True).fill(password)
            page.get_by_role("button", name="登录", exact=True).click()
            expect(page.locator("#identity")).to_contain_text(
                "顾客" if kind == "customer" else "管理员" if account == "web_admin" else "店员"
            )

        def logout() -> None:
            page.get_by_role("button", name="退出登录", exact=True).click()
            expect(page.locator("#identity")).to_have_text("游客")

        def nav(name: str) -> None:
            page.locator("#navigation button").filter(has_text=name).click()
            expect(page.locator("#page-title")).to_have_text(name)
            expect(page.locator("#feedback")).not_to_contain_text("正在读取")

        try:
            page.goto(args.url, wait_until="networkidle")
            api("/reports/sales?start_date=2026-01-01&end_date=2026-12-31", expected=401)
            shot("01_guest")
            login("web_admin")
            product = api(
                "/products",
                "POST",
                {
                    "name": "W10验收" + tag,
                    "description": "第10周定价与库存核验",
                    "price": "200.00",
                    "model_provider": "Other",
                    "token_amount": str(400000000 + (int(tag[:6], 16) % 1000000) * 4),
                    "required_upstream_tokens": "100",
                    "status": "active",
                },
            )
            pid = product["product_id"]
            account = api(
                "/accounts",
                "POST",
                {
                    "account_name": "W10账号" + tag,
                    "provider": "Other",
                    "total_quota": "1000",
                    "safety_threshold": "200",
                    "status": "active",
                    "expires_at": "2030-12-31",
                },
            )
            aid = account["account_id"]
            nav("库存校正记录")
            page.locator("#primary-action").click()
            page.locator("#editor [name=product_id]").select_option(str(pid))
            page.locator("#editor [name=account_id]").select_option(str(aid))
            page.locator("#editor [name=change_amount]").fill("300")
            page.locator("#editor [name=reason]").fill("第10周验收额度校正")

            def lose_committed_response(route: Route) -> None:
                response = route.fetch()
                assert response.status == 200
                route.abort("connectionreset")

            page.route("**/api/v1/inventory/adjustments", lose_committed_response, times=1)
            page.get_by_role("button", name="确认校正库存", exact=True).click()
            expect(page.locator("#editor .form-message")).to_contain_text("服务暂时无法连接")
            pending_key = page.evaluate(
                "JSON.parse(sessionStorage.getItem('tokenhub.inventoryAdjustment.pending')).operation_key"
            )
            shot("02a_committed_response_lost")
            page.locator("#close-editor").click()
            page.locator("#primary-action").click()
            expect(page.locator("#editor [name=reason]")).to_be_disabled()
            assert pending_key == page.evaluate(
                "JSON.parse(sessionStorage.getItem('tokenhub.inventoryAdjustment.pending')).operation_key"
            )
            page.get_by_role("button", name="重试原校正请求", exact=True).click()
            expect(page.locator("#editor-content")).to_contain_text("库存校正已保存")
            shot("02_adjustment")
            page.get_by_role("button", name="重试原校正请求", exact=True).click()
            expect(page.locator("#editor-content")).to_contain_text("库存校正已保存")
            records = api(f"/inventory/adjustments?account_id={aid}")
            assert len(records["items"]) == 1, records
            assert records["items"][0]["after_current_quota"] == "1300", records
            events.append(
                {"check": "committed response lost, reopen and retry same key", "result": "PASS"}
            )
            page.locator("#close-editor").click()
            nav("销售统计")
            expect(page.locator("#sales-summary")).to_be_visible()
            shot("03_sales_admin")
            logout()
            customer = "w10_" + tag
            api(
                "/auth/register",
                "POST",
                {
                    "account": customer,
                    "email": customer + "@example.invalid",
                    "password": password,
                    "password_confirm": password,
                },
            )
            page.reload(wait_until="networkidle")
            logout()
            login(customer, "customer")
            order = api("/orders", "POST", {"items": [{"product_id": pid, "quantity": 1}]})
            oid = order["order_id"]
            detail = api(f"/orders/{oid}")
            assert detail["order"]["total_amount"] == "190.00", detail
            issued = int(detail["order"]["total_tokens"])
            nav("订单管理")
            row = page.locator("#table-body tr").filter(has_text=str(oid)).first
            row.get_by_role("button", name="详情", exact=True).click()
            expect(page.locator("#editor-content")).to_contain_text("190.00")
            expect(page.locator("#editor-content")).to_contain_text("amount-v1")
            shot("04_discount_snapshot")
            page.locator("#close-editor").click()
            api(f"/orders/{oid}/pay", "POST")
            api("/usage", "POST", {"product_id": pid, "tokens_used": str(issued // 4)})
            api(f"/orders/{oid}/refund", "POST")
            refunds = api("/refunds")
            refund = next(r for r in refunds["items"] if r["order_id"] == oid)
            assert refund["refund_amount"] == "142.50", refund
            nav("退款账本")
            shot("05_discount_refund")
            api("/reports/sales?start_date=2026-01-01&end_date=2026-12-31", expected=403)
            logout()
            login("web_staff")
            api("/inventory/adjustments", "POST", {}, expected=403)
            nav("销售统计")
            shot("06_sales_staff")
            nav("补货任务")
            page.get_by_role("button", name="计算补货建议", exact=True).click()
            page.locator("#editor [name=product_id]").select_option(str(pid))
            page.locator("#editor [name=account_id]").select_option(str(aid))
            page.locator("#editor [name=minimum_quota]").fill("2000")
            page.locator("#editor [name=target_quota]").fill("3000")
            page.get_by_role("button", name="计算建议量", exact=True).click()
            expect(page.locator(".recommendation-result")).to_contain_text("1,700")
            shot("07_replenishment_recommendation")
            page.get_by_role("button", name="按建议创建补货任务", exact=True).click()
            page.get_by_role("button", name="确认提交", exact=True).click()
            expect(page.locator("#editor")).not_to_be_visible()
            tasks = api("/restocks")
            task = next(t for t in tasks["items"] if t["account_id"] == aid)
            api(f"/restocks/{task['task_id']}/complete", "POST", {"actual_amount": "100"})
            nav("补货任务")
            shot("08_restock_completed")
            logout()
            login("web_admin")
            api(f"/orders/{oid}/settle", "POST")
            nav("销售统计")
            shot("09_sales_after_refund")
            logout()
            events.append(
                {"check": "discount/refund/recommendation/adjustment and roles", "result": "PASS"}
            )
        finally:
            (args.evidence / "manifest.json").write_text(
                json.dumps(
                    {"events": events, "screenshots": pictures}, ensure_ascii=False, indent=2
                ),
                encoding="utf-8",
            )
            browser.close()
    print("PASS Week10 Edge browser workflow")


if __name__ == "__main__":
    main()
