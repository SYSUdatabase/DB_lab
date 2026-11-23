# 补做第10周遗漏项：普通 Windows 受限账户入口验收（WebXY1123R）

第10周记录中“普通 Windows 账户对第10周增量的运行验收”一直标为待补做（见[第10周结果](../../week10/README.md)）。本记录于 2026-11-23 补做，不倒填日期；验收对象是当前代码（第10—12周增量均已安装），因此同时核对第11周触发器与第12周事务在受限账户下能否正常写入。

| 项目 | 取值 |
|---|---|
| 电脑 | LAPTOP-OJSK2J30，SQL Server Express `localhost\SQLEXPRESS` |
| 代码 | 本地 main `3ec0ff3` |
| 部署位置 | 仓库临时副本 `E:\Claude产物\DB_lab_runtime_33d5cc`（受限账户无法进入用户目录下的正式仓库；副本经肖懿明确同意，验收后已删除） |
| 实验库 | `TokenHubDB_v01/v10/v11_WebXY1123R`，`tools/app_prepare.py --suffix WebXY1123R --with-week10 --with-week11 --with-week12`，退出码 0 |
| 运行账户 | `LAPTOP-OJSK2J30\TokenHubWebR`，计划任务 `TokenHub-TokenHubWebR`，由 `tools/setup_web_runtime.ps1` 创建 |
| 端口 | 5072（见下文“过程中的问题”） |
| 时间 | 2026-11-23 下午（UTC+8），审计记录时间 14:05—14:17 |

## 结果

| 核对 | 结果 | 证据 |
|---|---|---|
| 运行身份 | `run_web.ps1` 在运行账户下执行 `tools/runtime_identity.py`：`login=LAPTOP-OJSK2J30\TokenHubWebR`，`sysadmin=0`，`db_owner=0`，三项越权（读基表、改商品、DDL）均拒绝，商品目录可读 | [runtime_identity.log](runtime/runtime_identity.log) |
| SQL 端角色 | 该登录不属于任何服务器角色，数据库角色只有 `app_runtime` | [sql_principal_check.log](runtime/sql_principal_check.log) |
| Windows 端 | 账户不属于任何本地组；计划任务 RunLevel 为 Limited；监听 `127.0.0.1:5072` 的进程属主为 `TokenHubWebR` | [windows_runtime.json](runtime/windows_runtime.json) |
| HTTP 冒烟 | 首页 200，商品接口 `OK`、10 项 | [http_smoke.json](runtime/http_smoke.json) |
| 第10周接口 | 管理员登录后：销售统计（10 行）、补货建议、库存校正（OpenAI 账号 #1，1301000→1302000）、同一 operation_key 重放不再增加库存、校正记录列表，全部 200 | [week10_http.json](runtime/week10_http.json) |
| 订单完成（第11周触发器、第12周事务） | 顾客下单并支付订单 #112，状态变为 paid；同一订单再次支付返回 409 `BUSINESS_RULE` | [business_http.json](runtime/business_http.json) |
| 模拟调用 | 顾客消费 1000 Token，上游库存扣减 1200（按每份上游消耗折算），200 | 同上 |
| 补货入库（第12周事务） | 店员创建补货任务 #13 并以实际量 8000 完成，账号 #1 库存 1300800→1308800；同一任务再次完成返回 409，库存不变 | 同上 |
| 审计登录名 | 审计表共 4 行，`login_name` 全部为 `LAPTOP-OJSK2J30\TokenHubWebR`；`operator` 分别为 `employee:8`（库存校正 2 行）、`user:44`（调用扣减）、`employee:7`（补货） | [audit_login_check.json](runtime/audit_login_check.json) |
| 服务端日志 | `instance/webapp.log` 54 行，无 `DATABASE_ERROR`、`DATABASE_UNAVAILABLE` 等服务端错误；唯一一条 ERROR 是浏览器脚本故意重复注册触发的唯一约束（2627） | [webapp.log](runtime/webapp.log) |

结论：受限运行账户下，第10周三个接口、第11周订单完成触发器与库存审计触发器、第12周订单完成与补货入库事务均正常执行，没有因权限报错；审计表记录的登录名是实际运行账户。

## 过程中的问题

- **端口。** 笔记本的 5050 端口已被 11-17 启动的另一个网站进程占用（属主为肖懿本人账户），未改动该进程，`setup_web_runtime.ps1` 改用 `-Port 5060`。Edge 拒绝访问 5060（`ERR_UNSAFE_PORT`，该端口在浏览器的禁用端口表内），于是停止任务、把副本 `instance/runtime.json` 的端口改为 5072 后重启任务。5060 时已完成的一次第10周库存校正（审计第 1 行）保留在结果中；其余核对均在 5072 上重做。
- **旧浏览器脚本。** `tools/stage2_browser_e2e.py` 运行到管理员“新增商品”按钮时超时（[browser_attempt.log](runtime/browser_attempt.log)）：该脚本按第9周界面编写，此后加入运营概览等页面，界面已对不上。修复该脚本属于第10周另一项遗留（旧业务浏览器重跑），本轮不处理，业务流程改用 HTTP 接口完成，接口与页面调用的是同一组路由。
- **清理脚本。** `tools/cleanup_reproduction.ps1` 要求仓库目录名为 `DB_lab`，并要求备份路径与仓库路径一致，在临时副本上无法运行。因此：计划任务先停用、停止并删除；三个数据库按确切名称 `SET SINGLE_USER ... DROP DATABASE`，核对已不存在；SQL 登录 `LAPTOP-OJSK2J30\TokenHubWebR` 已删除；用仓库的 `tools/batch_logon_right.ps1` 撤销了该账户的“作为批处理作业登录”权限；两份备份随副本一起删除；副本与临时工作目录已删除，验收所用的随机实验密码只保存在临时目录中，已一并删除。
- **尚未完成的清理。** 运行账户 `TokenHubWebR` 运行过后，其用户配置一直处于加载状态，无法删除（与 2026-11-06 相同）。账户本身、`C:\Users\TokenHubWebR` 用户配置需在肖懿自行重启电脑后删除。该账户已没有计划任务、SQL 登录和批处理登录权限。
- 正式仓库的目录权限全程未改动；运行账户的读取授权只加在临时副本上，副本已删除。

## 待写入 AI 使用记录的内容（暂存）

AI 使用文档的修改正等待肖懿确认，本轮内容先记于此：肖懿要求补做第10周遗留的普通 Windows 受限账户入口验收，重点核对受限账户下触发器、事务与审计写入，并明确同意在 `E:\Claude产物\` 下临时建仓库副本、做完删除；清理若需重启，由他本人重启，不远程重启。AI 用新批次 WebXY1123R 完成上述核对（结果见上），遇到 5050 被占、5060 被浏览器禁用、旧浏览器脚本与现界面不符、清理脚本不适用于副本四个问题，处理方式如上；运行账户与用户配置待重启后删除。

（2026-11-23 补记）上面暂存的内容已写入 [AI 使用文档](../../../docs/ai使用文档.md) 与 [详细日志](../../../docs/ai_usage_log.md)。
