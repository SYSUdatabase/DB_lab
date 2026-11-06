# 报告截图重截（WebXY1106S）

第二阶段报告复核时发现：原图 14（`17_第二顾客数据隔离.png`）停在第二位顾客登录后的商品目录页，没有进入订单列表；原图 22、23 截于数据加载完成之前，表格显示“正在读取数据…”；员工管理截图仍是 11 月 4 日姓名列修复前的界面。本批次修正截图脚本后，从空库重建并重新截图，用于替换报告中的图 14 与图 16—22。截图为 Edge/Playwright 自动执行，不是组员逐张手动操作。

| 项目 | 取值 |
|---|---|
| 电脑 | LAPTOP-OJSK2J30（与 [WebXY1105F](../WebXY1105F/README.md) 同一台） |
| 数据库 | `TokenHubDB_v01/v10/v11_WebXY1106S`，`localhost\SQLEXPRESS` |
| 网站 | 本人账户启动的预览服务 `DB_LAB_PREVIEW=1`，`127.0.0.1:5051`；不用于受限账户核验 |
| 时间 | 2026-11-06（UTC+8） |

## 脚本修正

- `tools/stage2_browser_e2e.py`：第二位顾客 `web_other` 登录后先进入“订单管理”，断言列表中没有订单 #112，再截 `17_第二顾客数据隔离.png`；执行清单中该事件新增 `visible_order_ids` 字段（本次为空列表）。
- `tools/stage2_employee_browser.py`：`09_普通店员没有员工管理入口.png` 与 `11_新店员可登录但无管理权限.png` 截图前等待“正在读取”提示消失。

网站代码与 SQL 未改。两处共新增 7 行，Ruff check 与 format 检查通过。

## 结果

- 建库：`tools/app_prepare.py --suffix WebXY1106S` 全部阶段 PASS，日志见 [source](../../source_WebXY1106S/)、[week6/v11](../../week6/v11/WebXY1106S/)、[webapp](../../webapp/WebXY1106S/)。
- 原业务流程：22 张截图、42 条事件 PASS，[manifest](browser/manifest.json)。订单编号与 WebEmp26A01 相同为 #112；第二位顾客的订单列表为空，直接请求 `GET /api/v1/orders/112` 返回 403 `FORBIDDEN`（请求 `678fa865a5d444818b004504d077f503`）。
- 员工管理流程：11 张截图、10 条事件 PASS，[manifest](employees/manifest.json)。页面表头为“员工姓名”，不再出现“套餐 #undefined”。普通店员 `web_staff` 请求员工 API 返回 403（请求 `320fcac18606405b8276312501a5daa3`）。`09_…` 与 `11_…` 两张截图逐字节相同：两名店员登录后看到的界面一致，报告只放入其中一张。
- 业务脚本第一次运行时，截第一张图即报 `Page.screenshot: Protocol error (Page.captureScreenshot): Unable to capture screenshot`，没有产生任何业务事件。失败现场保留在 [browser_attempt1_failed](browser_attempt1_failed/failed.json)；目录改名后同一批次重跑通过。

截图后抽查目视：图 14、店员两张截图、新增店员列表与事件一致。

## 清理

停止 5051 预览服务；执行 `tools/cleanup_reproduction.ps1 -Suffix WebXY1106S -KeepEvidence`，三个数据库、两份备份和批次备份目录删除并核验 PASS。保留本目录与上述构建日志；临时实验密码文件随 `instance/` 一并删除。
