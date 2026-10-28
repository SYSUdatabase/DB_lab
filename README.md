# TokenHub：第二阶段数据库应用（第 5—9 周）

本仓库当前交付**第 5—9 周的数据库重构与 Web 应用**。课程提交版本称为 **v1.0**；其中 v1.0 完成规范化迁移，内部 v1.1 继续完善库存、订单、Token 批次及退款业务。Web 页面运行在 v1.1 上。原第 1—4 周资料已统一归档至 [archive](archive/README.md)，保留作为 v0.1 迁移基线的正式 SQL 和测试工具。

## 交付内容与入口

| 周次 | 当前成果 | 主要文件 |
|---|---|---|
| 第 5 周 | ER 图、实体及联系、主外键、候选码、旧结构问题 | [ER 图及设计说明](week5/README.md) |
| 第 6 周 | 函数依赖、范式分析、无损分解、迁移与回归、v1.1 规则完善 | [依赖分析](week6/dependency_normalization.md)、[重构方案](week6/redesign_decisions.md)、[迁移](sql/v10/migration.sql)、[回归](sql/v10/regression.sql)、[第六周说明](week6/README.md) |
| 第 7—9 周 | Flask 四层 Web、顾客注册和登录、商品/订单/库存/补货/退款、角色及异常控制 | [Web 操作手册](docs/webapp.md)、[应用代码](webapp/)、[应用测试](tests/)、[Web SQL](sql/app/) |
| 最终报告 | 设计、实验过程、图示、实际运行与异常证据、总结 | **[第二阶段报告](report/stage2_report.md)** |
| 测试证据 | 浏览器真实截图、请求编号、SQL 对账及完整测试结果 | **[第二阶段证据](result/stage2/WebStage2A02/README.md)**、[原有测试记录](result/webapp/README.md) |
| 过程材料 | AI 使用记录、组内分工、复现说明 | [AI 使用文档](docs/ai使用文档.md)、[详细日志](docs/ai_usage_log.md)、[组内分工](docs/team_division.md) |

## 系统架构

```text
HTML / CSS / JavaScript（webapp/templates、webapp/static）
  ↓ /api/v1/* HTTP + CSRF
Flask 路由和统一错误处理（webapp/__init__.py）
  ↓
业务层：身份、权限、输入规则（webapp/services.py）
  ↓
数据访问层：pyodbc 参数化、事务及回滚（webapp/dao.py）
  ↓
SQL Server（sql/v01、sql/v10、sql/v11、sql/app）
```

[应用 ER 图](report/er_diagram_app.png) · [可编辑 ER 源码](report/er_diagram_app.mmd) · [模块结构图](report/overview_modules.png) · [模块可编辑源码](report/overview_modules.mmd) · [数据字典](docs/app_data_dictionary.md)。

顾客可注册、创建订单、模拟支付、查询余额、模拟 Token 消费、申请部分退款；店员查询订单/库存、受控补货及取消待支付单；管理员另可维护商品/上游账号、处理符合规则的删除及模拟退款结算。**页面“待处理（pending）”表示等待顾客支付，不是等待店员审核。** 真实支付、真实 API 计费和真实资金结算不在本演示范围。

## 环境及从空库复现

Windows 64 位、Python ≥3.11、SQL Server Express（默认 `localhost\SQLEXPRESS`）、ODBC Driver 18、`sqlcmd`、PowerShell 5.1+。建库用户必须具备 SQL Server 创建、备份和还原实验库的权限；本地网站预览仅监听 127.0.0.1。

在项目根目录运行：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
$env:PATH = "$pwd\.venv\Scripts;$env:PATH"
$env:DB_LAB_DEMO_PASSWORD = Read-Host "设置12至72字节的实验密码"
.\.venv\Scripts\python.exe tools/app_prepare.py --suffix WebNewRun01
```

**每次使用从未用过的后缀**；准备程序会从 v0.1 建库→备份/还原→v1.0 迁移→v1.1 扩展→安装 Web 数据库过程，并自动生成演示账户。拒绝覆盖既有数据库和同名结果目录。

仅用于本机开发验收的启动方式：

```powershell
$env:DB_LAB_APP_DATABASE = "TokenHubDB_v11_WebNewRun01"
$env:DB_LAB_SECRET = [Guid]::NewGuid().ToString("N") + [Guid]::NewGuid().ToString("N")
$env:DB_LAB_PREVIEW = "1"
.\.venv\Scripts\python.exe -m webapp
```

浏览器访问 **http://127.0.0.1:5050/**。测试账户为顾客 `web_customer`、`web_other`，员工入口为店员 `web_staff`、管理员 `web_admin`，密码是准备时自行设置的实验密码。顾客也可在登录对话框注册新账号。**不要提交真实密码、`instance/` 内容或 SQL 登录密钥。**

正式受限 Windows 账户部署见 [Web 操作手册](docs/webapp.md) 的 `tools/setup_web_runtime.ps1`；开发预览的 `app_runtime_probe` 测试**不能替代**使用真实普通 Windows 身份的数据库权限验收。

## 测试与交付证据

专门的新数据库上运行，自动测试会写入模拟业务数据，不应在演示主库或他人实验库上重复运行：

```powershell
$env:DB_LAB_TEST_DATABASE = "TokenHubDB_v01_WebNewRun01"
$env:DB_LAB_APP_DATABASE = "TokenHubDB_v11_WebNewRun01"
$env:DB_LAB_DEMO_PASSWORD = Read-Host "输入本次实验密码"
$env:DB_LAB_PREVIEW = "1"
$env:DB_LAB_SECRET = "仅本地测试使用的随机密钥"
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\.venv\Scripts\ruff.exe check webapp tests tools
```

本次第二阶段独立浏览器证据以 `TokenHubDB_v11_WebStage2A02` 为对象：**22 张 Edge 真页面截图、42 项操作/API 记录、25 项只读 SQL 对账检查全部通过**。另有新库 `WebSign28A` 的 **66 项完整单元与集成测试通过**；详细范围、异常结果和局限见[阶段报告](report/stage2_report.md)与[证据索引](result/stage2/WebStage2A02/README.md)。截图为自动化浏览器执行，并非组员手工签收。

**两名组员已经实际参与网站验收**：陈诗翰第一名先在其环境测试；阮依成第二名亲自测试本机网站登录和订单显示，发现缺少注册入口并推动修复。22张Edge截图为补充自动化证据；[全角色手动验收清单](docs/stage2_acceptance.md)供可选的独立环境复现。真实受限Windows账户启动仍待验证。

## 目录概览

```text
sql/v01/              迁移所需原始建库及数据脚本（保留执行依赖）
sql/v10/              migration.sql、regression.sql（课程 v1.0）
sql/v11/              业务加固及退款、库存扩展
sql/app/              Web 应用过程与受限顾客注册
week5/、week6/        ER、函数依赖、范式、重构与回归
webapp/、tools/       Web 页面/业务/DAO 与准备、验收脚本
tests/                安全、SQL、事务和 HTTP 自动化测试
report/               第二阶段报告、ER 图和渲染源码
docs/                 Web 操作手册、数据字典、AI 日志及分工
result/               第二阶段实际证据、迁移及测试日志
archive/              第 1—4 周旧报告、历史说明、完整原日志和旧证据
```

所有可编辑图源及 `report/render_app_er.py`、`report/render_overview_modules.py` **保留**。项目运行不依赖它们，但后续修改图像时可以重新导出；旧材料归档映射见 [archive/README.md](archive/README.md)。
