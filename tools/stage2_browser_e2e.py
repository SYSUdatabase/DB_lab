"""Real Edge browser acceptance: screenshots and redacted JSON evidence.

Run only against a newly prepared isolated Web DB. Requires optional playwright
(pip install playwright) and locally installed Microsoft Edge. No screenshots are
mocked; all are produced by Edge against live Flask + SQL Server.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime
from pathlib import Path

from playwright.sync_api import expect, sync_playwright

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suffix", required=True)
    parser.add_argument("--url", default="http://127.0.0.1:5051")
    args = parser.parse_args()
    if not re.fullmatch(r"Web[A-Za-z0-9]{3,12}", args.suffix):
        raise SystemExit("Refusing non-isolated database suffix")
    directory = ROOT / "result" / "stage2" / args.suffix / "browser"
    directory.mkdir(parents=True, exist_ok=False)
    shots = directory / "screenshots"
    shots.mkdir()
    password = (
        (ROOT / "instance" / "stage2_evidence_password.txt").read_text(encoding="utf-8").strip()
    )
    if not 12 <= len(password) <= 72:
        raise SystemExit("Invalid private experiment password")
    events: list[dict[str, object]] = []
    pictures: list[dict[str, str]] = []
    account = "stage2_new_A01"
    email = "stage2_new_A01@example.invalid"
    product = "Stage2验收套餐P_A01"
    account_name = "Stage2上游账号A01"
    order_id = None

    def mark(name: str, **details: object) -> None:
        events.append({"check": name, **details})
        print("PASS", name, flush=True)

    with sync_playwright() as playwright:
        edge = Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")
        browser = playwright.chromium.launch(headless=True, executable_path=str(edge))
        context = browser.new_context(
            viewport={"width": 1440, "height": 900}, device_scale_factor=1
        )
        page = context.new_page()
        page.set_default_timeout(18000)

        def shot(name: str) -> None:
            file = shots / f"{name}.png"
            page.screenshot(path=str(file), full_page=True, animations="disabled")
            digest = hashlib.sha256(file.read_bytes()).hexdigest()
            pictures.append({"file": file.name, "sha256": digest})
            print("SCREENSHOT", file.name, flush=True)

        def api(path: str, method: str = "GET", data: dict | None = None) -> tuple[int, dict]:
            result = page.evaluate(
                """async ({path, method, body}) => {
                    const s = await (await fetch('/api/v1/auth/session')).json();
                    const opts={method,headers:{'Content-Type':'application/json','X-CSRF-Token':s.data.csrf}};
                    if(method!=='GET')opts.body=JSON.stringify(body||{});
                    const res=await fetch('/api/v1'+path,opts);
                    return {status:res.status, json:await res.json()};
                }""",
                {"path": path, "method": method, "body": data},
            )
            payload = result["json"]
            mark(
                "HTTP " + method + " " + path.split("?")[0],
                status=result["status"],
                code=payload.get("code"),
                request_id=payload.get("request_id"),
            )
            return int(result["status"]), payload

        def nav(name: str) -> None:
            page.locator("#navigation button").filter(has_text=name).click()
            expect(page.locator("#page-title")).to_have_text(name)
            expect(page.locator("#feedback")).not_to_contain_text("正在读取")

        def login(kind: str, username: str) -> None:
            page.get_by_role("button", name="登录账户", exact=True).click()
            page.get_by_label("登录入口").select_option(kind)
            page.get_by_label("账号", exact=True).fill(username)
            page.get_by_label("密码", exact=True).fill(password)
            page.get_by_role("button", name="登录", exact=True).click()
            expect(page.locator("#identity")).to_contain_text(
                "顾客" if kind == "customer" else ("管理员" if username == "web_admin" else "店员")
            )
            mark("Login " + username, role=kind)

        def logout() -> None:
            page.get_by_role("button", name="退出登录", exact=True).click()
            expect(page.locator("#identity")).to_have_text("游客")
            mark("Logout")

        def submit() -> None:
            page.get_by_role("button", name="确认提交", exact=True).click()
            expect(page.get_by_role("status")).to_contain_text("操作成功")

        try:
            page.goto(args.url + "/", wait_until="networkidle")
            expect(page.locator("#page-title")).to_have_text("商品目录")
            shot("01_游客商品目录")
            mark("Guest catalog", count=page.locator("#table-body tr").count())

            page.get_by_role("button", name="登录账户").click()
            shot("02_登录入口")
            page.get_by_role("button", name=re.compile("注册顾客账户")).click()
            shot("03_顾客注册表单")
            page.get_by_label("账号", exact=False).fill(account)
            page.get_by_label("邮箱").fill(email)
            page.get_by_label("密码（至少12字节）").fill(password)
            page.get_by_label("确认密码").fill(password)
            page.get_by_role("button", name="创建顾客账号").click()
            expect(page.locator("#identity")).to_contain_text("顾客")
            shot("04_注册成功自动登录")
            mark("Register new customer auto-login")

            logout()
            page.get_by_role("button", name="登录账户").click()
            page.get_by_role("button", name=re.compile("注册顾客账户")).click()
            page.get_by_label("账号", exact=False).fill(account)
            page.get_by_label("邮箱").fill("stage2_other_A01@example.invalid")
            page.get_by_label("密码（至少12字节）").fill(password)
            page.get_by_label("确认密码").fill(password)
            page.get_by_role("button", name="创建顾客账号").click()
            expect(page.locator(".form-message")).to_contain_text("重复")
            shot("05_重复账号拒绝")
            mark("Duplicate username rejected without account creation")
            page.get_by_role("button", name="取消", exact=True).click()

            page.get_by_role("button", name="登录账户").click()
            page.get_by_label("登录入口").select_option("customer")
            page.get_by_label("账号", exact=True).fill("web_customer")
            page.get_by_label("密码", exact=True).fill("wrong-password-123")
            page.get_by_role("button", name="登录", exact=True).click()
            expect(page.locator(".form-message")).to_contain_text("账号或密码不正确")
            shot("06_错误密码拒绝")
            mark("Invalid login rejected")
            page.get_by_role("button", name="取消", exact=True).click()

            login("employee", "web_admin")
            page.get_by_role("button", name="新增商品", exact=True).click()
            page.get_by_label("套餐名称").fill(product)
            page.get_by_label("模型供应商").select_option("Other")
            page.get_by_label("单价").fill("12.00")
            page.get_by_label("套餐 Token").fill("135791")
            page.get_by_label("每套餐上游消耗").fill("135791")
            submit()
            nav("商品目录")
            shot("07_管理员新增商品")
            status, products = api("/products?q=Stage2")
            assert status == 200
            item = next(row for row in products["data"]["items"] if row["name"] == product)
            product_id = int(item["product_id"])
            mark("New product ID", product_id=product_id)
            page.get_by_role("button", name="新增商品").click()
            page.get_by_label("套餐名称").fill("Stage2重复档位A01")
            page.get_by_label("模型供应商").select_option("Other")
            page.get_by_label("单价").fill("15.00")
            page.get_by_label("套餐 Token").fill("135791")
            page.get_by_label("每套餐上游消耗").fill("135791")
            page.get_by_role("button", name="确认提交").click()
            expect(page.locator(".form-message")).to_contain_text("重复")
            shot("08_商品唯一约束拒绝")
            mark("Duplicate provider plus Token rejected")
            page.get_by_role("button", name="取消", exact=True).click()

            nav("上游库存")
            page.get_by_role("button", name="新增上游账号").click()
            page.get_by_label("账号名称").fill(account_name)
            page.get_by_label("模型供应商").select_option("Other")
            page.get_by_label("初始总额度").fill("1000000")
            page.get_by_label("安全阈值").fill("1000")
            submit()
            shot("09_管理员新增库存账号")
            accounts_status, accounts = api("/inventory")
            assert accounts_status == 200
            account_data = next(
                row for row in accounts["data"]["items"] if row["account_name"] == account_name
            )
            account_id = int(account_data["account_id"])
            mark(
                "New upstream inventory",
                account_id=account_id,
                initial_quota=str(account_data["current_quota"]),
            )
            logout()

            login("customer", "web_customer")
            nav("商品目录")
            page.get_by_label("搜索记录").fill(product)
            page.get_by_role("button", name="搜索", exact=True).click()
            expect(page.locator("#table-body tr")).to_have_count(1)
            page.locator("#table-body tr").first.get_by_role("button", name="选购").click()
            shot("10_顾客订单表单")
            page.get_by_role("button", name="提交订单").click()
            expect(page.locator("#page-title")).to_have_text("订单管理")
            status, orders = api("/orders")
            assert status == 200 and orders["data"]["items"]
            order_id = int(orders["data"]["items"][0]["order_id"])
            mark("Created draft", order_id=order_id)
            shot("11_顾客待支付订单")
            row = page.locator("#table-body tr").filter(has_text=str(order_id)).first
            row.get_by_role("button", name="模拟支付").click()
            submit()
            row = page.locator("#table-body tr").filter(has_text=str(order_id)).first
            expect(row).to_contain_text("已支付")
            shot("12_订单模拟支付成功")
            nav("Token 余额")
            shot("13_支付后余额")
            nav("调用记录")
            page.get_by_role("button", name="模拟调用").click()
            page.get_by_label("商品编号").select_option(str(product_id))
            page.get_by_label("消费 Token").fill("50000")
            submit()
            shot("14_Token调用扣减")
            status, usage = api("/usage")
            assert status == 200 and usage["data"]["items"]
            mark("Successful usage", used=50000)

            status, bad = api("/usage", "POST", {"product_id": product_id, "tokens_used": -1})
            assert status == 400 and bad["code"] == "INVALID_INPUT"
            status, inj = api("/products?q=%27%3B%20DROP%20TABLE%20Users%3B--")
            assert status == 200 and inj["code"] == "OK"
            mark("Input rejection and SQL injection-as-search are safe")
            nav("订单管理")
            row = page.locator("#table-body tr").filter(has_text=str(order_id)).first
            row.get_by_role("button", name="申请退款").click()
            submit()
            shot("15_顾客部分退款订单")
            nav("退款账本")
            shot("16_退款金额待结算")
            status, refunds = api("/refunds")
            ref = next(x for x in refunds["data"]["items"] if int(x["order_id"]) == order_id)
            mark(
                "Refund recorded",
                order_id=order_id,
                amount=str(ref["refund_amount"]),
                refunded_tokens=str(ref["refundable_tokens"]),
                consumed_tokens=str(ref["consumed_tokens"]),
            )
            s1, r1 = api(f"/orders/{order_id}/refund", "POST", {})
            s2, r2 = api(f"/orders/{order_id}/refund", "POST", {})
            assert s1 == s2 == 200 and r1["data"] == r2["data"]
            mark("Repeated refund idempotent")
            status, declined = api("/usage", "POST", {"product_id": product_id, "tokens_used": 1})
            assert status == 409
            mark("Spent/refunded balance cannot be reused")
            logout()

            login("customer", "web_other")
            status, deny = api(f"/orders/{order_id}")
            assert status == 403 and deny["code"] == "FORBIDDEN"
            shot("17_第二顾客数据隔离")
            mark(
                "Cross-customer order blocked",
                order_id=order_id,
                code=deny["code"],
                request_id=deny["request_id"],
            )
            logout()

            login("employee", "web_staff")
            nav("上游库存")
            row = page.locator("#table-body tr").filter(has_text=account_name).first
            row.get_by_role("button", name="补货").click()
            page.get_by_label("计划补货数量").fill("10000")
            submit()
            nav("补货任务")
            row = page.locator("#table-body tr").first
            row.get_by_role("button", name="完成补货").click()
            page.get_by_label("实际补货").fill("8000")
            submit()
            shot("18_店员补货完成")
            status, deny = api("/products", "POST", {})
            assert status == 403
            shot("19_店员无商品管理权限")
            mark("Staff cannot create products", code=deny["code"], request_id=deny["request_id"])
            logout()

            login("employee", "web_admin")
            nav("退款账本")
            row = page.locator("#table-body tr").filter(has_text=str(order_id)).first
            row.get_by_role("button", name="模拟结算").click()
            submit()
            shot("20_管理员模拟退款结算")
            mark("Administrator registered simulated settlement")
            status, deny = api(f"/orders/{order_id}", "DELETE", {})
            assert status == 409
            mark(
                "Paid/refunded orders cannot be deleted",
                code=deny["code"],
                request_id=deny["request_id"],
            )
            logout()

            # The unauthorized API response is displayed by the actual browser.
            response = page.goto(args.url + "/api/v1/orders", wait_until="load")
            assert response is not None and response.status == 401
            assert "UNAUTHENTICATED" in page.locator("body").inner_text()
            shot("21_游客访问订单401")
            mark("Unauthenticated API blocked", status=401)
            page.goto(args.url + "/", wait_until="networkidle")
            shot("22_验收结束游客界面")

            manifest = {
                "database": "TokenHubDB_v11_" + args.suffix,
                "url": args.url,
                "timestamp": datetime.now().isoformat(timespec="seconds"),
                "browser": "Microsoft Edge headless / Playwright, real live HTTP",
                "mode": "automatic browser execution; NOT human review",
                "order_id": order_id,
                "product_id": product_id,
                "account_id": account_id,
                "events": events,
                "screenshots": pictures,
                "result": "PASS",
                "not_tested": [
                    "real card payouts",
                    "independent group member review",
                    "real restricted Windows service account",
                ],
            }
            (directory / "manifest.json").write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            print(
                "PASS BROWSER E2E", len(pictures), "screenshots", len(events), "events", flush=True
            )
        except Exception as exc:
            try:
                shot("99_失败现场")
            except Exception:
                pass
            (directory / "failed.json").write_text(
                json.dumps(
                    {
                        "database": args.suffix,
                        "order_id": order_id,
                        "events": events,
                        "screenshots": pictures,
                        "error_type": type(exc).__name__,
                        "error": str(exc)[:2500],
                    },
                    ensure_ascii=False,
                    indent=2,
                ),
                encoding="utf-8",
            )
            raise
        finally:
            browser.close()


if __name__ == "__main__":
    main()
