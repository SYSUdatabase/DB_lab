"""Real Edge employee-management acceptance, normal and error screenshots."""

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
    parser.add_argument("--url", default="http://127.0.0.1:5052")
    parser.add_argument("--run-id", default="employees")
    args = parser.parse_args()
    if not re.fullmatch(r"Web[A-Za-z0-9]{3,12}", args.suffix):
        raise SystemExit("Only isolated Web database suffixes")
    directory = ROOT / "result" / "stage2" / args.suffix / args.run_id
    directory.mkdir(parents=True, exist_ok=False)
    shots = directory / "screenshots"
    shots.mkdir()
    demo_pw = (
        (ROOT / "instance" / "employee_evidence_password.txt").read_text(encoding="utf-8").strip()
    )
    username = "employeeA02" if args.run_id == "employees_verified" else "employeeA01"
    password, new_password = "employee-A01-Start123", "employee-A01-Reset456"
    screenshots: list[dict[str, str]] = []
    events: list[dict[str, object]] = []

    with sync_playwright() as tool:
        browser = tool.chromium.launch(
            headless=True,
            executable_path=r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        )
        page = browser.new_page(viewport={"width": 1440, "height": 900})
        page.set_default_timeout(15000)

        def mark(name: str, **info: object) -> None:
            events.append({"event": name, **info})
            print("PASS", name, info, flush=True)

        def screenshot(name: str) -> None:
            path = shots / (name + ".png")
            page.screenshot(path=str(path), full_page=True, animations="disabled")
            screenshots.append(
                {"file": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            )
            print("SCREENSHOT", name, flush=True)

        def csrf() -> str:
            return page.evaluate(
                "async()=> (await (await fetch('/api/v1/auth/session')).json()).data.csrf"
            )

        def api(path: str, method: str = "GET", data: dict | None = None) -> tuple[int, dict]:
            result = page.evaluate(
                """async x=>{
                  const s=await (await fetch('/api/v1/auth/session')).json();
                  const options={method:x.method,headers:{'Content-Type':'application/json','X-CSRF-Token':s.data.csrf}};
                  if(x.method!=='GET')options.body=JSON.stringify(x.payload||{});
                  const response=await fetch('/api/v1'+x.path,options);
                  return {status:response.status,body:await response.json()};
                }""",
                {"path": path, "method": method, "payload": data},
            )
            body = result["body"]
            mark(
                "HTTP " + method + " " + path,
                status=result["status"],
                code=body.get("code"),
                request_id=body.get("request_id"),
            )
            return result["status"], body

        def login(account: str, password_value: str = demo_pw):
            page.get_by_role("button", name="登录账户").click()
            page.get_by_label("登录入口").select_option("employee")
            page.get_by_label("账号", exact=True).fill(account)
            page.get_by_label("密码", exact=True).fill(password_value)
            page.get_by_role("button", name="登录", exact=True).click()
            expect(page.locator("#identity")).to_contain_text("已登录")

        def logout():
            page.get_by_role("button", name="退出登录").click()
            expect(page.locator("#identity")).to_have_text("游客")

        def submit():
            page.get_by_role("button", name="确认提交", exact=True).click()
            expect(page.locator("#editor")).not_to_be_visible()

        try:
            page.goto(args.url + "/", wait_until="networkidle")
            login("web_admin")
            page.locator("#navigation button").filter(has_text="员工管理").click()
            expect(page.locator("#page-title")).to_have_text("员工管理")
            screenshot("01_管理员员工列表")
            mark("Administrator sees employee management")

            page.get_by_role("button", name="新增店员", exact=True).click()
            screenshot("02_新增店员表单")
            page.get_by_label("姓名", exact=True).fill("员工管理验收甲")
            page.get_by_label("登录账号", exact=False).fill(username)
            page.get_by_label("初始密码", exact=True).fill(password)
            page.get_by_label("确认密码", exact=True).fill(password)
            page.get_by_role("button", name="创建店员", exact=True).click()
            expect(page.locator("#editor")).not_to_be_visible()
            expect(page.locator("#table-body tr").filter(has_text=username)).to_have_count(1)
            screenshot("03_新增店员成功")
            status, data = api("/employees?page=1&q=")
            assert status == 200
            employee = next(x for x in data["data"]["items"] if x["account"] == username)
            employee_id = int(employee["employee_id"])
            assert employee["role"] == "staff" and employee["status"] == "active"
            assert "password_hash" not in employee
            mark("Staff is exclusively staff and no hash exposed", employee_id=employee_id)

            page.get_by_role("button", name="新增店员", exact=True).click()
            page.get_by_label("姓名", exact=True).fill("重复账户")
            page.get_by_label("登录账号", exact=False).fill(username)
            page.get_by_label("初始密码", exact=True).fill(password)
            page.get_by_label("确认密码", exact=True).fill(password)
            page.get_by_role("button", name="创建店员", exact=True).click()
            expect(page.locator(".form-message")).to_contain_text("重复")
            screenshot("04_重复店员账号被拒")
            page.get_by_role("button", name="取消", exact=True).click()

            row = page.locator("#table-body tr").filter(has_text=username)
            row.get_by_role("button", name="修改姓名").click()
            page.get_by_label("姓名", exact=True).fill("验收员工改名")
            submit()
            row = page.locator("#table-body tr").filter(has_text=username)
            expect(row).to_contain_text("验收员工改名")
            screenshot("05_管理员修改店员姓名")

            row.get_by_role("button", name="重置密码").click()
            page.get_by_label("新密码（至少12字节）", exact=True).fill(new_password)
            page.get_by_label("确认新密码").fill(new_password)
            submit()
            screenshot("06_管理员重置密码后")
            mark("Password reset completed")

            row = page.locator("#table-body tr").filter(has_text=username)
            row.get_by_role("button", name="停用", exact=True).click()
            submit()
            row = page.locator("#table-body tr").filter(has_text=username)
            expect(row).to_contain_text("已停用")
            screenshot("07_店员停用保留记录")

            row.get_by_role("button", name="重新启用").click()
            submit()
            row = page.locator("#table-body tr").filter(has_text=username)
            expect(row).to_contain_text("在职")
            screenshot("08_店员重新启用")
            status, data = api(
                "/employees",
                "POST",
                {
                    "name": "Escalate",
                    "account": "escalate01",
                    "password": password,
                    "password_confirm": password,
                    "role": "admin",
                },
            )
            assert status == 400 and data["code"] == "INVALID_INPUT"
            mark("Client admin-role injection rejected")

            logout()
            login("web_staff")
            expect(page.locator("#navigation")).not_to_contain_text("员工管理")
            status, data = api("/employees?page=1&q=")
            assert status == 403 and data["code"] == "FORBIDDEN"
            expect(page.locator("#feedback")).not_to_contain_text("正在读取")
            screenshot("09_普通店员没有员工管理入口")
            mark("Staff forbidden on admin page and API")
            logout()
            page.goto(args.url + "/api/v1/employees?page=1", wait_until="load")
            assert page.locator("body").inner_text().find("UNAUTHENTICATED") != -1
            screenshot("10_游客不能查看员工列表")
            mark("Guest access rejected")
            page.goto(args.url + "/", wait_until="networkidle")
            login(username, new_password)
            expect(page.locator("#identity")).to_contain_text("店员")
            expect(page.locator("#navigation")).not_to_contain_text("员工管理")
            expect(page.locator("#feedback")).not_to_contain_text("正在读取")
            screenshot("11_新店员可登录但无管理权限")
            mark("New staff login succeeded after password reset")

            manifest = {
                "database": "TokenHubDB_v11_" + args.suffix,
                "date": datetime.now().isoformat(timespec="seconds"),
                "browser": "Microsoft Edge / Playwright (real web UI, automatic)",
                "execution": "automated browser, not participant manually clicking screenshots",
                "employee_id": employee_id,
                "events": events,
                "screenshots": screenshots,
                "status": "PASS",
            }
            (directory / "manifest.json").write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            print("PASS EMPLOYEE BROWSER", len(screenshots), "screenshots", len(events), "events")
        except Exception as ex:
            try:
                screenshot("99_失败现场")
            except Exception:
                pass
            (directory / "failure.json").write_text(
                json.dumps(
                    {"type": type(ex).__name__, "message": str(ex)[:2500], "events": events},
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
