# 新环境从零部署与受限 Windows 账户验收（WebXY1105F）

本轮在一台此前没有部署过本项目的 Windows 电脑上，从空库开始构建，并以普通 Windows 账户运行网站，核对该账户在 SQL Server 中的实际权限。浏览器截图仍为 Edge/Playwright 自动执行，不是组员逐张手动操作。

| 项目 | 取值 |
|---|---|
| 电脑 | LAPTOP-OJSK2J30，Windows 10 家庭中文版（Build 26300） |
| 数据库 | SQL Server 2025 Express（17.0.1145.4），`localhost\SQLEXPRESS` |
| Python | 3.14.3；计划任务使用 Windows PowerShell 5.1 |
| 仓库位置 | 用户目录之外的独立副本（E 盘），见下文“部署位置” |
| 实验库 | `TokenHubDB_v01/v10/v11_WebXY1105F` |
| 运行账户 | `LAPTOP-OJSK2J30\TokenHubWebF`，计划任务 `TokenHub-TokenHubWebF` |
| 时间 | 2026-11-06 00:47—00:54（UTC+8） |

## 结果

- 建库：`tools/app_prepare.py --suffix WebXY1105F` 全部阶段 PASS，日志见 [source](../../source_WebXY1105F/)、[week6/v11](../../week6/v11/WebXY1105F/)、[webapp](../../webapp/WebXY1105F/)。
- 运行身份：`run_web.ps1` 在运行账户下执行 `tools/runtime_identity.py`，结果为 [runtime_identity.log](runtime/runtime_identity.log)：`login=LAPTOP-OJSK2J30\TokenHubWebF`，`sysadmin=0`，`db_owner=0`，读取 `dbo.Users`、修改 `dbo.Products`、在 `app` 架构建表三项均被拒绝（229/262），`app.[Execute] products.list` 返回非空目录。
- SQL 端只读核对 [sql_principal_check.log](runtime/sql_principal_check.log)：该 Windows 登录不属于任何服务器角色，数据库角色只有 `app_runtime`。
- Windows 端 [windows_runtime.json](runtime/windows_runtime.json)：账户不属于任何本地组，计划任务 RunLevel 为 Limited；监听 `127.0.0.1:5050` 的进程及两个 `python -m webapp` 进程的属主均为 `TokenHubWebF`。
- HTTP 冒烟 [http_smoke.json](runtime/http_smoke.json)：首页 200，商品接口 `OK`、10 项。
- 浏览器流程（连接上述受限账户运行的 5050 服务）：原业务 22 张截图、42 条事件 PASS，[manifest](browser/manifest.json)；员工管理 11 张截图、10 条事件 PASS，[manifest](employees/manifest.json)。`browser/manifest.json` 的 `not_tested` 字段是脚本内固定文本，本轮受限账户的核对结果以 `runtime/` 下文件为准。
- 截图已抽查目视：订单支付、店员补货、新增店员页面内容与事件一致。员工列表第二列表头显示为“套餐名称”、行内显示“套餐 #undefined”，第9周 WebEmp26A01 截图中已有相同现象，属于原有页面显示问题，本轮未修改。

## 部署中发现并修正的问题

此前的构建都在原开发电脑上进行，下列问题只在新电脑上出现。每次失败都保留日志，修正后换新后缀重跑，失败批次的数据库和备份已按 RunId 清理。

| 批次 | 失败现象 | 原因 | 修正 |
|---|---|---|---|
| WebXY1105B | `regression_v11.sql` R12：对象名 `TokenHubDB_v01_A.sys.tables` 无效（[日志](../../week6/v11/WebXY1105B/regression_v11.sql.log)） | `build_sandbox.py` 只把 `TokenHubDB_v01_A.dbo.` 替换为本次源库，R12 的 `.sys.tables`/`.sys.views` 仍指向原电脑才有的 `TokenHubDB_v01_A` | 测试脚本循环中改为替换 `TokenHubDB_v01_A.` 前缀（1 行） |
| WebXY1105C | 计划任务从未运行，安全日志 4625：登录类型 4，0xC000015B（[记录](../WebXY1105C/runtime/first_start_failure.json)） | 运行账户没有“作为批处理作业登录”权限，这台 Windows 10 家庭版在注册任务时没有自动授予 | 新增 `tools/batch_logon_right.ps1`；`setup_web_runtime.ps1` 授予、`cleanup_reproduction.ps1 -RemoveRuntime` 删除账户前撤销（各 2 行） |
| WebXY1105D | 任务退出码 1，`instance` 内文件 DACL 为空（[记录](../WebXY1105D/runtime/first_start_failure.json)） | `icacls instance /inheritance:r /grant:r ...(OI)(CI)... /T` 作用到文件后清空了文件权限；临时目录对照实验可复现，去掉 `/T` 后文件正常继承 | 去掉该行的 `/T` |
| WebXY1105E | 任务退出码 1，`Set-Location : 拒绝访问`（[记录](../WebXY1105E/runtime/first_start_failure.json)） | 仓库位于 `C:\Users\<用户>\Desktop`，运行账户无法进入他人用户目录 | 本轮改用用户目录之外的仓库副本；`setup_web_runtime.ps1` 开头检查该情况并直接报错（3 行），手册补充部署位置要求 |
| WebXY1105F 首次启动 | 首个请求返回后服务退出，任务退出码 1 | `run_web.ps1` 设为 `$ErrorActionPreference='Stop'`，Windows PowerShell 5.1 把重定向的原生 stderr（Flask 请求日志）当作终止错误 | 启动前改为 `Continue`，成败仍由 `$LASTEXITCODE` 判断（1 行） |

诊断 WebXY1105E 与 WebXY1105F 首次启动时，为了以同一运行账户捕获 stderr，临时重置了该批次运行账户的密码并注册诊断任务 `TokenHub-Diag`，诊断结束后删除该任务；上表最后一行修正后，WebXY1105F 的正式任务重新启动并完成上述全部核对。

## 部署位置

运行账户只获得仓库目录本身的读取权限，不应获得 `C:\Users\<用户>` 的访问权限，因此仓库必须放在用户目录之外（如 `D:\`、`E:\`）。本轮所用 E 盘根目录对已登录用户开放“修改”权限，运行账户对仓库文件因此不只是只读；这不影响 SQL 权限核对，但正式部署时应选择只开放读取的位置。

## 清理

验收后停用运行任务并重启电脑，使运行账户的用户配置卸载，再删除 TokenHubWeb、TokenHubWebE、TokenHubWebF 三个运行账户及其计划任务、SQL 登录、用户配置和批处理登录授权，删除全部 `WebXY1105*` 数据库与备份。WebXY1105C/D/E 的构建均为 PASS、与本批次重复，只保留 `result/stage2/<后缀>/runtime/` 下的失败现场；WebXY1105B 保留完整构建日志。
