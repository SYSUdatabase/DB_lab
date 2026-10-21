# API Token 中转站数据库实验 v0.1

本仓库交付数据库课程第 1～4 周成果：经营场景、关系模式、建库与样例数据、CRUD、多表查询、统计视图、完整性与最小权限。正式运行入口为 `sql/` 与 `tools/run_v01.ps1`。

2026-10-02 已修复样例数据时间顺序、历史负余额、过期账号调用和证据验收问题，在两个新空库完成真实复现。结果见 [验收证据](result/README.md)，设计与实验总结见 [阶段报告](report/stage_report.md)。

## 业务范围

用户购买 OpenAI、Claude、Gemini 的 Token 套餐；订单明细保存价格和 Token 快照。支付形成按用户/provider 管理的余额，调用扣减余额及上游账号额度，库存流水保留变动，日/周/月汇总用于经营分析。

进入数据库：用户、员工、角色、商品、订单与明细、上游账号、库存与流水、Token 余额与调用、使用汇总、补货任务及异常。

暂不进入数据库：明文密码、真实 API Key、Prompt 和完整请求/响应、支付平台详细流水、设备/IP、图片和非核心日志。样例凭据均为教学占位符。真实登录、支付/退款、补货事务、会员写操作与并发控制留到后续阶段。

销售只计算 `Orders.status='paid'`，金额采用订单明细下单快照。样例 refunded 订单已净冲销，不为当前余额形成充值。

## 业务流程

流程中的规则均由 `sql/v01/verify.sql`（VFY）、`sql/v01/role.sql`（R）、`sql/v01/constraint.sql`（C）和 `sql/v01/query.sql`（Q）逐条验收，编号见 [当前验收](#当前验收)。

### 会员：购买与使用 Token

1. **注册/登录**：写入 `Users`，记录 `created_at`。此后所有订单与调用都必须晚于该时间（VFY12）。
2. **浏览商品**：读取 `v_ProductCatalog`，只暴露在售商品的价格、Token 档位和上游折算量。
3. **选购下单**：写入 `Orders`（`status='pending'`，`paid_at` 必须为 NULL）与 `OrderDetails`（保存商品、单价、Token 数快照）。
4. **支付**：状态改为 `paid` 并写入 `paid_at`。`CK_Orders_payment_time`（在 `sql/v01/constraint.sql` 中补充创建）强制 paid/refunded 必须有 `paid_at` 且不早于 `created_at`，pending/cancelled 必须为 NULL。
5. **余额到账**：按用户 + provider 写入或累加 `TokenBalances.remaining_tokens`。同一秒内先到账、后扣款（VFY13）。
6. **调用扣费**：写入 `TokenUsageLogs`，同时减少会员 `TokenBalances` 与上游账号 `Inventory.current_quota`。账号须在 `created_at`～`expires_at` 有效期内，且 `provider` 与商品匹配；到期边界当刻不可调用（VFY12）。
7. **查看记录**：会员经 `v_MyOrders`、`v_MyBalances`、`v_MyUsage` 只读本人数据（R01～R17）。

### 会员与客服：售后处理

1. **提交咨询**：订单异常进入 `ExceptionLog`，记录关联订单、处理人与处理时间。
2. **客服受理**：经 `v_CustomerService` 查看工单与订单上下文。
3. **处理**：pending/cancelled 订单由店员经 `v_StaffOrderQueue` 工作队列改状态；refunded 订单不再形成充值。

### 店员：日常运营

1. **商品维护**：维护 `Products` 上下架与价格档位。
2. **库存管理**：调整 `Inventory`，每次变动写 `InventoryLog`，保留变动前后数量、操作人与时间。
3. **异常巡检**：查看 `RestockTask` 补货任务与 `ExceptionLog` 异常工单。

### 店长：经营分析

1. **汇总查询**：经 `v_ProductSales`、`v_MemberSpending`、`v_OrderDetail` 查看销售与消费汇总。
2. **库存健康**：经 `v_InventoryStatus` 监控额度水位；额度触底生成 `RestockTask`。
3. **用量趋势**：按日/周/月汇总 `UsageSummary` 观察调用量与 Token 消耗。
4. **权限审计**：经 `v_CustomerService` 与权限矩阵核对四类角色的实际授权范围。

### 系统约束

余额按 provider 分账，充值只认 `paid_at`、只计 `paid` 订单。最终余额非负不足以证明过程正确，因此 `sql/v01/verify.sql` 逐事件回放历史余额。同秒事件先到账后消费，保证任何时刻余额非负。

## 角色与权限

| 角色 | 当前数据库能力 |
|---|---|
| 店长 hub_manager | 14 张业务表 CRUD，7 个共享视图读取；无 DDL/CONTROL/固定高权限角色 |
| 店员 hub_staff | 共享经营/客服视图读取；只通过工作队列更新 pending/cancelled 的 status |
| 会员 hub_customer | 在售目录和本人订单、余额、调用视图；无基表读取和写权限 |
| 游客 hub_guest | 仅在售目录 |

`dbo.Roles` 是应用层角色数据；四个 DATABASE ROLE 执行数据库授权。演示用户使用 WITHOUT LOGIN 和 EXECUTE AS，不是生产登录体系。第一周会员下单、支付、改资料及店员退款职责的阶段差异见 [角色流程](report/role_workflow.md)，后续以校验身份的存储过程实现。

## 目录

```text
DB_lab/
├─ README.md / ROADMAP.md / CLAUDE.md
├─ sql/                 正式 SQL 与说明
├─ tools/               当前生成器、准备、复现及证据工具
├─ tests/               Python 与 SQL Server 回归测试
├─ report/              阶段报告、ER 图、角色流程和知识导图
├─ docs/                复现说明、AI 日志、分工、任务书
├─ result/              当前版本日志、签名和分页截图
├─ plan/                已确认计划与执行状态
└─ archive/             各周过程材料、旧版证据与路径说明
```

所有正式运行工具独立于 archive；旧生成器和旧日志供历史追溯，不作为当前验收入口。

## 环境与复现

本次实测：Windows、SQL Server Express 17.0.1135.8、`localhost\SQLEXPRESS`、ODBC sqlcmd、PowerShell、Python venv。使用 Windows 身份验证，不保存登录密码。

在仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_v01.ps1
```

省略参数时自动生成新的 `TokenHubDB_v01_*` 库名和 `run_*` 结果标签，终端打印实际库名。也可显式指定未占用的名称：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_v01.ps1 `
  -DatabaseName TokenHubDB_v01_MyRun -RunLabel run_my_run
```

结果目录和数据库已存在时拒绝覆盖，换一个名称即可。`-ExecutionPolicy Bypass` 只作用于本次进程。详情见 [复现与验证](docs/reproduction.md)。

脚本顺序：`00_create_database` → `01_create_tables` → `02_insert_data` → `03_crud_demo` → `view` → `query` → `constraint` → `role` → `verify` → `signature`。视图先创建，因为 Q09 引用了库存视图。SSMS 单独执行须启用 SQLCMD 模式并提供 `DatabaseName`。

## 生成样例与测试

通常复现直接使用已提交 SQL；修改生成器后才重新生成。

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m tools.datagen
.\.venv\Scripts\ruff.exe check tools tests
.\.venv\Scripts\ruff.exe format --check tools tests
$env:DB_LAB_TEST_DATABASE = 'TokenHubDB_v01_FinalA'
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

测试库必须已经按本版本构建。SQL 集成测试通过事务注入反例并回滚，不删除数据库。未设置测试库时，Python 测试执行，SQL 集成测试明确标记 skipped；不能将 skipped 计为通过。

生成器保证注册不晚于订单或调用、调用时账号有效且 provider 匹配、任意事件时刻余额非负。同秒付款先到账、调用后扣款。SQL DATETIME2 使用统一 Asia/Shanghai 本地时间；库存展示快照固定为 `2026-09-22 23:59:59`。账号当前 expired/suspended 状态不等于过去始终不可用，历史有效期按 created_at/expires_at 判断。

## 当前验收

- 14 表、10 视图、4 数据库角色、5 演示用户。
- 100 订单、184 明细、3000 调用；paid 订单 85，销售额 4228.90，售出 Token 92950000。
- 22 个回归测试、ruff 检查与格式检查通过。
- C01～C14、R01～R17、VFY01～VFY14 均通过；Q01～Q12 成功执行，并有业务结果核对。
- 注册前订单/调用、到期后调用、provider 不匹配、历史负余额均为 0。
- FinalA/FinalB 的 14 表签名逐字节一致；修复后签名与旧版不同，旧版材料单独归档。
- 当前有 22 组证据 SQL/日志、26 张分页输出控件截图，最终 PASS 完整可见。
- 第二名成员独立复现尚未登记；本次自动化回归不代表全组独立复核完成。

## 课程与协作材料

- [第四周原始任务书](docs/requirements/week4.docx) 与 [要求映射](docs/requirements/README.md)
- [SQL 说明](sql/v01/README.md)、[阶段报告](report/stage_report.md)、[角色流程](report/role_workflow.md)
- [结果证据](result/README.md)、[复现说明](docs/reproduction.md)
- [ai使用文档（第四周提交正文）](docs/ai使用文档.md)、[AI 详细日志](docs/ai_usage_log.md)、[组内分工](docs/team_division.md)、[修复记录](ROADMAP.md)
- [历史材料与迁移映射](archive/README.md)


## 第二阶段：第五周 ER 模型（2026-10-10）

第五周基于第一阶段 v0.1 **逆向分析** 14 张表、17 条 FK，明确实体标识、联系基数和参与约束，暂不修改既有表结构。正式交付入口是 [第五周 ER 设计审查](week5/README.md)，包含 [可编辑 ER 图](week5/er_diagram.mmd)、[SVG 图](week5/er_diagram.svg)、[数据字典](week5/data_dictionary.md)、[业务规则映射](week5/business_rules_mapping.md)、[v0.1 问题与保留项](week5/v01_issues.md)、[设计说明和真实只读验证](week5/design_validation.md)。

本周在现存 `TokenHubDB_v01_A` 上只读核验了 100 订单、184 明细、68 个多明细订单；0 张无明细订单并不意味着数据库外码强制“一单至少一明细”。这四项规则在第五周登记为待决项；后续已于 2026-10-14 确定业务方案，并在独立 v1.1 副本实施。第五周的 v0.1 ER 基线和运行入口保留不变。

## 第二阶段：第六周规范化与迁移（2026-10-14）

第六周入口：[规范化分析与迁移进度](week6/README.md)、[14 表函数依赖与范式判断](week6/dependency_normalization.md)、[有条件重构及无损/依赖保持](week6/redesign_decisions.md)、[当前证据](result/week6/README.md)、[执行计划](plan/week6-normalization-migration-plan.md)。

已针对旧 `TokenHubDB_v01_A` 完成备份、校验和隔离还原；迁移前源/副本业务基准一致。周期规范化方案已批准，随后在隔离库实际执行 `sql/v10/migration.sql` 与 `sql/v10/regression.sql`，R01–R12 通过；详情及历史业务异常见下文。

## 第六周执行结果补充（2026-10-14）

已根据用户批准，在隔离副本 `TokenHubDB_v10_W6_20261014` 实施有依据的固定周期规范化：`UsagePeriod` 99 条，`UsageSummaryCore` 3394 条，物理表 15 张、真实外码 18 条，旧 `UsageSummary` 以只读兼容视图继续提供 10 列业务查询。原 `TokenHubDB_v01_A` 未修改，迁移前后源业务基准 SHA-256 一致。

正式入口：[第六周 README](week6/README.md)、[依赖与范式分析](week6/dependency_normalization.md)、[重构决策](week6/redesign_decisions.md)、[v1.0 可编辑 ER 图](week6/er_diagram_v10.mmd)、[v1.0 数据字典](week6/data_dictionary_v10.md)、[迁移脚本](sql/v10/migration.sql)、[回归脚本](sql/v10/regression.sql)及[结果证据](result/week6/README.md)。

回归 R01–R12、权限 VFY14 均通过，非权限业务基准 3763 行零差异；源库自带订单/调用时间不一致及历史负余额问题使旧 VFY12/VFY13 **未通过**。完整异常计数见第六周报告，不能以迁移成功替代原始数据修复。原 `sql/v01/02_insert_data.sql` 只适用于 v0.1，新 v1.0 写入应经 UsagePeriod/UsageSummaryCore。迁移与测试证据已进入第六周后续 Git 提交；以当前 `git log` 和 `git status` 为准。

## 第五周问题修复试验（v1.1 隔离库，2026-10-14）

[本轮修复明细与决策项](week6/v11/README.md)：在新副本 `TokenHubDB_v11_Issues_20261014` 中，对已完成订单、调用 provider/日期、已知弱引用和原子化消费增加前向校验；原 v0.1 与 v1.0 不变。与 v1.0 的 3763 条业务基准零差异，关联正反例及 R01–R12 通过。I02/I03/I04/I07 的业务选择已于 2026-10-14 确定并在 v1.1 副本实施；I01/I05/I06/I08/I09 尚有局部写入入口与旧数据问题。

## 用户批准后的 v1.1 I02/I03/I04/I07 修复（2026-10-14）

在隔离库 `TokenHubDB_v11_Issues_20261014` 已实施：同单同商品通过 quantity 合并；散客先登记 Users 后下单；新增上游账号自动生成且必须保留唯一库存；补货任务按 manual/system 决定是否必须有创建人。新增两个受控订单过程、三个触发器和 `RestockTask.created_source`，并提供 [v1.1 数据字典](week6/v11/data_dictionary_v11.md)、[可编辑 ER 图](week6/v11/er_diagram_v11.mmd)、[测试和限制](week6/v11/README.md)。新规则与先前 R01–R12 回归全部通过；业务数据 3763 条零差异。原库和 v1.0 结果库均未改。旧历史数据异常及其它写入入口的后续完善仍需独立处理。

## 交互式项目业务总览（2026-10-14）

独立 HTML 页面：[按 6 个板块理解 API Token 中转站](report/overview_modules.html)（首选入口，直接双击即可在浏览器离线打开）。包含 15 张 v1.0 物理表分组、业务流程导航、搜索、点击表后查看 PK/候选码/FK/业务要点；页面不连接数据库，不展示凭据。

适合先理解“用户 → 套餐订单 → 余额和 API 调用 → 上游库存 → 周期统计 → 运营处理”。其中 UsageSummary 是兼容视图而非第 16 张物理表；详细 18 条 FK 仍以 [第六周 ER 图](week6/er_diagram_v10.svg) 和 [目标数据字典](week6/data_dictionary_v10.md) 为准。备选静态总览保存在 [SVG](report/overview_modules.svg) 及 [Mermaid 源](report/overview_modules.mmd)；它们不覆盖第五/六周既有 ER 图。

## 第六周迁移前完整代码备份与独立复现（2026-10-14）

[完整历史代码 ZIP 和校验](archive/week6-pre-migration/README.md) 保存第六周开始前 `c8d4e64` 的全部 344 个 Git 跟踪项目文件；[一键复现脚本和说明](week6/reproduction/README.md) 可从该快照全新建 v0.1、备份/还原另一个数据库、执行第六周 `migration.sql`、运行 R01–R12 与 VFY01–VFY14 并对比业务基准。[两轮实际复现结果](result/week6/reproduction/README.md) 均 PASS（第二轮由脚本端到端执行），3763 条非权限业务记录零差异。

这一链路**不依赖原 `TokenHubDB_v01_A` 的本地数据**。标准旧代码重建的 v0.1 有 10 个视图并通过原始验证；原历史 `v01_A` 只有 9 个视图且带历史时间/余额异常，两者的结果须分开记录。


## v1.1 加固与合成历史数据修复（2026-10-17）

[部署与验收说明](week6/v11/README.md) 已补全第五周遗留问题的安全写入路径：受控支付、消费和补货；历史元数据的反向修改约束；余额/额度/明细与汇总的直接修改拦截；可验证的库存流水→调用事件关联。

在 **xiao_ruan 本机新建的隔离副本** `TokenHubDB_v11_Harden261017B` 中，先从未变更的 `TokenHubDB_v01_A` 备份、校验并还原，再依次迁移 v1.0、安装 v1.1、核对并修订来源可验证的固定种子合成历史数据，最后部署新约束。四类历史异常由 `20 / 402 / 225 / 1` 降为 **`0 / 0 / 0 / 0`**；账号配额、库存和流水对账通过；v1.1 适配的 **VFY01–VFY14**、新增 **X01–X10、Y01–Y04** 及原 v1.1 测试均通过。[修复审计及日志](result/week6/hardening/Harden261017B/) 已保存。

**版本边界**：原 v0.1_A/B/C/D、既有 v1.0 和队友 `sh` 电脑上的 `TokenHubDB_v11_Issues_20261014` 未更改，不能据本机副本核验推断远端旧库已经修复。此历史校正只适用于经固定种子指纹确认的合成样例；退款事务和第三阶段应用身份绑定仍需按业务规则另行开发。本轮未修改第二阶段报告。


## v1.1 统一版本与退款功能（2026-10-17）

当前完整可复现的 v1.1 版本已整合在 [week6/v11](week6/v11/README.md)，包含基础业务修复、历史合成样例修复、受控支付/消费/补货，以及退款与结算流水。**17 张表、20 个可信外码**；对应 [最新 ER](week6/v11/er_diagram_v11.png)、[数据字典](week6/v11/data_dictionary_v11.md) 和统一部署入口 `python -B .\week6\v11\run_full.py --suffix NewV11Run01`。

在 `xiao_ruan` 的新库 `TokenHubDB_v11_Full261017D`，独立一键复现及 VFY01–VFY14、X01–X10、Y01–Y04、RF01–RF06 均已通过。旧合成样例时间/余额异常在新副本中全部归零，旧 v0.1 不变。退款只退订单尚未消费的 Token 对应的成交价金额，已使用部分不退；数据库建立**应退款项**，实际金额仍须支付系统退款后凭证结算。未接入支付平台，不表示资金已自动到账。

原 `issue_fixes` 和 `hardening` 基础脚本将统一保存在 `week6/v11`，不再分成两套代码目录；历史日志/备份不清理。第二阶段报告未改动，队友 sh 原有 v1.1 尚未升级，本机新副本通过不代表远端已生效。

## 第7–9周 Web应用（2026-10-21）

第二阶段课程交付版本v1.0，数据库采用内部v1.1。新增Flask/Jinja/pyodbc应用，包含顾客/店员/管理员、商品与库存维护、订单明细、模拟支付/调用/补货/退款，业务规则仍为调用时扣库存。

- [运行配置与角色操作手册](docs/webapp.md)
- [第5–9周阶段报告](report/stage2_report.md)、[应用会话数据字典](docs/app_data_dictionary.md)
- [实施计划](plan/week7-9-webapp-plan.md)、[应用证据](result/webapp/README.md)
- [任务书](docs/requirements/week7-9.docx)

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-web.txt
$env:PATH = "$pwd\.venv\Scripts;$env:PATH"
$env:DB_LAB_DEMO_PASSWORD = Read-Host '设置本地样例密码，至少12字节'
.\.venv\Scripts\python.exe tools/app_prepare.py --suffix WebYourRun01
# 管理员PowerShell中配置普通运行账户，配置后访问 http://127.0.0.1:5050/
powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup_web_runtime.ps1 `
  -DatabaseName TokenHubDB_v11_WebYourRun01 -AccountName TokenHubWeb
```

账户与数据库配置均拒绝覆盖。当前会话无Windows管理员权限，专用账户实际启动验收尚未执行；SQL降权与Web验证结果见证据索引。旧版本入口和结果保留。

## Web 全角色人工验收流程

按“游客 → 管理员准备 → 顾客交易 → 店员运营 → 管理员收尾”的顺序操作。每一步都列出预期结果；结果不符时记录订单/账号/任务编号和页面请求编号，不把下列预期直接登记成已通过。运行配置见[应用手册](docs/webapp.md)，此前自动测试结果见[证据索引](result/webapp/README.md)。

### 0. 准备环境和记录表

1. 打开 [TokenHub](http://127.0.0.1:5050/)。页面已经登录时先点“退出登录”。
2. 为获得下文的确定数值，使用按应用手册创建的**全新实验库**；`web_customer` 的 `Other` 余额应为零，且没有该 provider 尚未消费的历史购买批次。已有数据不满足时另用新后缀准备库，不删除旧库或清空历史记录。仅换商品名称不能隔离同 provider 的 FIFO 批次。
3. 用本次建库时设置的样例密码登录。现有本机环境的密码由持有人在本地 `instance/demo_password.txt` 查看，不写入本文件、截图或提交。下列账户由准备工具创建，不提供注册页面。
4. 每次换身份都先退出，再选择正确的“登录入口”；不要在共享 Cookie 的两个标签页中同时扮演不同身份。需要并排比较时使用不同浏览器配置或无痕窗口。
5. 给验收对象名称附加本轮后缀，例如 `1021A`。下文用 `P/Q/R` 代表商品、`A/B` 代表上游账号、`O1～O6` 代表实际返回的订单编号、`T1/T2` 代表补货任务；它们不是数据库中的固定编号。商品编号可从顾客选择套餐下拉框或接口结果核对。

| 身份 | 登录入口 | 账户 | 需要覆盖的职责 |
|---|---|---|---|
| 游客 | 不登录 | — | 在售目录、搜索、分页、进入登录；不能访问受限业务 |
| 顾客 | 顾客登录 | `web_customer` | 本人订单和明细、取消草稿、模拟支付、余额、调用、退款及记录查询 |
| 第二位顾客 | 顾客登录 | `web_other` | 本人数据隔离，不能访问或操作第一位顾客的订单 |
| 店员 | 员工登录 | `web_staff` | 商品只读、全体订单/余额/调用/退款查询、取消待支付单、库存和补货 |
| 管理员 | 员工登录 | `web_admin` | 店员全部职责，加商品维护、账号维护、必要删除和模拟退款结算 |

页面每页20条；对象不在当前页时翻页，商品和订单还可使用搜索。查询和提交后等待列表或成功提示更新，再继续下一步。支付、API 调用、退款结算均为本地模拟。

建议按下表记录，失败时补充页面提示和请求编号；本流程编写完成不等于已经由组员人工执行。

| 检验人 / 日期 | 应用数据库 / Git 提交 | 步骤编号 | 对象实际编号 | 操作前值 → 操作后值 | 通过 / 失败 | 截图或请求编号 |
|---|---|---|---|---|---|---|
| 待填写 | 待填写 | 待填写 | 待填写 | 待填写 | 待填写 | 待填写 |

### 1. 游客与登录

| 编号 | 人工操作 | 预期结果 |
|---|---|---|
| G1 | 未登录打开首页，浏览“商品目录”；搜索 `OpenAI`，再搜索不存在的名称，最后清空搜索。 | 只展示在售商品；筛选结果和总数更新；无匹配时显示空状态，清空后恢复。没有库存、余额或订单导航。 |
| G2 | 核对“上一页/下一页”和记录总数。 | 第一页“上一页”禁用，最后一页“下一页”禁用；超过20条时可翻页，无重复漏页的异常表现。样例不足21条时记录“翻页成功路径未检验”，不要写已通过。 |
| G3 | 点击“登录购买”，先填错误密码，再用 `web_customer` 和正确密码登录。 | 错误密码得到简明提示；正确登录后右上角为“顾客 · 已登录”，出现订单、余额、调用、退款导航。密码不出现在页面提示中。 |
| G4 | 退出登录，再按第7节的方法调用 `checkApi('/orders')`。 | 恢复游客目录，订单请求返回 HTTP 401；不能借退出前页面继续访问本人记录。 |

### 2. 管理员准备商品与上游账号

以 `web_admin` 从“员工登录”进入。这里只准备数据，后续再检验管理员收尾职责。

| 编号 | 人工操作 | 预期结果 |
|---|---|---|
| A1 | “商品目录 → 新增商品”，创建下表的 P、Q、R，状态均选“在售”。 | 三笔新增成功，列表显示名称、供应商、Token档位和价格。记录实际商品编号。 |
| A2 | 编辑 R：价格由 `0.50` 改为 `0.75`，修改描述，依次切换“下架”“停售”，最后恢复“在售”。 | 编辑后重新打开能看到保存值；退出为游客时，下架/停售的 R 不出现，在售时出现；管理员能查询各状态商品。价格小于1元仍可提交。 |
| A3 | 删除从未被使用的 R，并确认。 | 删除成功，再搜索名称没有记录。P、Q 保留供后续订单使用。 |
| A4 | 再次新增一个 `Other + 100000 Token` 商品；另试价格 `0`、负数数量或遗漏名称。 | 重复供应商/档位被约束拒绝；非法字段由表单或后端拒绝，不新增半条数据，页面不泄露 SQL。 |
| A5 | “上游库存 → 新增上游账号”，创建 A、B：供应商 `Other`，初始总额度 `1000000`，安全阈值 `10000`，状态 `active`；到期时间留空或选未来。 | 每个新账号各出现一条库存记录，可用额度均为 `1000000`，无需另建库存。记录 A、B 编号。 |
| A6 | 编辑 B：修改名称、安全阈值为 `20000`，先暂停再恢复有效，保存后重新打开核对。 | 元数据修改生效，额度仍为 `1000000`；编辑页面没有直接覆盖总额度/已用额度的入口。 |
| A7 | 删除尚无调用、流水和补货引用的 B。 | 账号及其配对库存一起删除；列表不残留孤立库存。A 保留用于补货。 |

| 代号 | 套餐名称示例 | 供应商 | 单价 | 套餐 Token | 每套餐上游消耗 |
|---|---|---|---:|---:|---:|
| P | `人工验收P-1021A` | Other | 12.00 | 100000 | 100000 |
| Q | `人工验收Q-1021A` | Other | 20.00 | 200000 | 200000 |
| R | `人工验收R-1021A` | Other | 0.50 | 300000 | 300000 |

同一供应商与Token档位组合唯一；若这些档位已存在，说明不是本流程假定的全新环境，先核对准备步骤，不覆盖原商品。顾客支付不会扣库存，实际模拟调用才会扣减。服务端会选择符合条件且编号最小的上游账号，**不保证调用使用新建的 A**。

### 3. 顾客订单与明细

退出管理员，使用 `web_customer` 登录。先查看“Token 余额”，确认 Other 无余额行或为0；记录其它 provider 的原值。

| 编号 | 人工操作 | 预期结果 |
|---|---|---|
| C1 | “创建订单”：P 数量1加入明细，再把 P 数量1加入一次，再加入 Q 数量1，提交并记为 O1。 | 状态为“待处理”（pending）；O1“详情”仅两条商品明细，P 数量2、Q 数量1；金额 `44.00`，Token `400000`。说明同商品在数据库中合并数量。 |
| C2 | O1“详情”中将 P 数量改为3，点“更新数量”。 | P 小计 `36.00`；订单金额 `56.00`，Token `500000`。关闭再打开详情，值一致。 |
| C3 | 删除 O1 的 Q 明细。 | 只剩 P，订单金额 `36.00`、Token `300000`。 |
| C4 | O1“详情 → 增加一项商品”，重新加入 Q 数量1，提交后重开详情。 | 恢复两项明细；金额 `56.00`、Token `500000`。 |
| C5 | 再删除 Q，将 P 更新为数量1。 | O1 最终仅 P，单价快照 `12.00`，金额 `12.00`、Token `100000`；尚未支付，余额不变。 |
| C6 | 暂时退出，以管理员把 P 当前价格改为 `15.00`；再以原顾客登录，打开 O1。 | 目录显示 `15.00`，O1 原明细仍为 `12.00`；不按新价格重算历史快照。 |
| C7 | O1“增加一项商品”，再加入 P 数量1。 | 仍是一条 P 明细，数量2；沿用首次快照价 `12.00`，订单金额 `24.00`、Token `200000`。 |
| C8 | 新建 O4，仅选 P 数量1；提交后在详情中删除唯一明细，再尝试“模拟支付”。 | O4 金额、Token均为0，明细为空；支付被拒绝，仍为 pending，余额不变。保留 O4 给店员取消、管理员删除。 |
| C9 | 新建含 P 的 O5，点“取消”并确认。 | O5 状态为“已取消”，明细仍保留；没有余额入账或库存扣减。 |
| C10 | 再新建含 P 的 O6，保持待支付，供管理员继承职责检查。 | 创建成功，保持 pending，不改变余额和库存。 |

订单列表可按编号搜索，详情应与列表汇总一致。后续每次查找以记录的实际编号为准，不依赖“第一行就是某笔订单”。

### 4. 顾客支付、调用和三类退款

保持 `web_customer` 身份。可先让店员按第5节记录当前 Other 账号额度，再回到顾客操作，以便比较库存变化。

| 编号 | 人工操作 | 预期结果 |
|---|---|---|
| C11 | 对 O1 点“模拟支付 → 确认提交”。 | O1 变为“已支付”，Other余额增加 `200000`；上游库存不变，其它 provider 余额不变。 |
| C12 | 查看 O1 详情；再用第7节接口方法重复支付。 | 页面不再提供可修改的明细控件；重复支付 HTTP 409，Other余额不重复增加。 |
| C13 | “调用记录 → 模拟调用”，选择 P，消费Token填 `50000`。 | 新增一条调用记录，消费 `50000`；Other余额从 `200000` 减至 `150000`。P上游折算比为1，实际被选择账号的库存减少 `50000`；详情字段可用第7节查询接口辅助核对。 |
| C14 | 再试调用 `150001` Token；另试 `0` 或负数。 | 余额不足或参数校验拒绝；余额仍 `150000`，没有新成功调用，库存不再减少。记录失败前后值。 |
| C15 | O1 点“申请退款 → 确认提交”，再查看“退款账本”。 | O1为“部分退款”；回收 `150000` Token，已消费 `50000`，应退 `18.00`（`24 × 150000 / 200000`）；Other余额为0，结算为“待模拟结算”。退款不回补已消费的上游库存。 |
| C16 | 用第7节接口方法重复请求 O1 退款，再刷新账本。 | HTTP 200，返回原订单结果；仍只有一笔该订单退款，金额与Token不重复扣减。 |
| C17 | 按 P 的新目录价创建 O2，数量1，模拟支付后立即申请退款，不进行调用。 | 成交价 `15.00`，发放并回收 `100000` Token；应退 `15.00`，O2为“已退款”，Other余额回到0。O1、O2可以同时待结算。 |
| C18 | 再创建 O3，P 数量1，支付后模拟调用 `100000` Token，再尝试退款。 | 消费后Other余额为0；退款被拒绝，O3仍为paid，无该订单的新退款账本项；已有调用保留。 |
| C19 | 分别查看本人“订单管理”“Token余额”“调用记录”“退款账本”，核对 O1～O6 和成功/失败次数。 | 查询只含本人数据；失败调用/失败退款不增加成功记录。当前这轮 Other 余额为0，成功调用共 `150000` Token，上游库存合计减少 `150000`（不计另外完成的补货）。 |
| C20 | 退出，以 `web_other` 顾客身份登录，查询上述四类记录，并尝试读取、支付或退款 O1。 | 看不到 `web_customer` 的这些记录；直接接口访问 O1被拒绝（403），不能通过修改URL操作别人的订单。 |

退款金额按明细成交小计比例逐项取到分，不按当前目录价格计算。上述绝对余额和退款金额依赖第0节的干净 Other 账本条件；若已有旧批次，FIFO会先消费旧批次，此时应先隔离验收数据，不能把期望金额硬套在旧数据上。

### 5. 店员运营职责

以 `web_staff` 从“员工登录”进入。

| 编号 | 人工操作 | 预期结果 |
|---|---|---|
| S1 | 查看“商品目录”，搜索 P；核对页面按钮。 | 能查商品，包括已下架记录；没有“新增商品”“编辑”“删除”权限入口。 |
| S2 | 查看“订单管理”，搜索 O1、O4、O5，打开详情；再查看“Token余额”“调用记录”“退款账本”。 | 能查询不同顾客及原样例的运营数据，能看到 O1/O2 的应退款项；不能替顾客模拟支付、调用或申请退款，不能修改已付明细。 |
| S3 | 在 O4 上点“取消”并确认。 | 空草稿O4从pending变为cancelled；店员没有“删除空单”能力。O5本来已取消，不再提供再次取消入口。 |
| S4 | “上游库存”中找到 A，记录额度 `1000000`；点该行“补货”，计划补货 `10000`，创建 T1。 | 任务创建成功，当前库存仍 `1000000`；创建任务本身不增加库存。 |
| S5 | “补货任务”中找到 T1，点“完成补货”，实际补货填 `8000` 并确认。 | T1为“已完成”，计划 `10000`、实际 `8000`；A库存变为 `1008000`，按实际数量增加。再次完成按钮消失，重复接口请求被拒绝且额度不再增加。 |
| S6 | 在“补货任务 → 创建补货任务”再次为 A 新建 T2，计划 `2000`，暂不完成。 | 从任务页也能创建任务；A库存仍为 `1008000`。保留 T2 给管理员完成。 |
| S7 | 用第7节方法尝试新增商品、修改/删除 A、删除 O4 或结算 O1。 | 这些直接API请求均403，不能依靠绕过隐藏按钮获得管理员能力。失败后原记录不变。 |

上游库存页是查看和受控补货入口，没有任意覆盖库存数值的操作。检查 C13/C19 的库存扣减时，根据调用记录中的 `account_id` 或 Other 所有账号总额核对；不要默认消耗发生在 A。若 Other有多页账号，合计必须包含全部页。

### 6. 管理员收尾及继承职责

退出店员，以 `web_admin` 登录。

| 编号 | 人工操作 | 预期结果 |
|---|---|---|
| A8 | 重做 S1/S2 的跨顾客查询：商品、订单详情、余额、调用、库存、补货、退款七个板块分别查看。 | 管理员能读取运营数据；此前顾客的订单快照、消费记录和应退款金额保持一致。 |
| A9 | 对仍待支付的 O6执行“取消”。 | 取消成功；证明管理员继承店员的取消职责，但不获得顾客的购买/调用身份。 |
| A10 | 在“补货任务”完成店员创建的 T2，实际填 `2000`；再由管理员自己创建并完成 A 的 T3，实际填 `1000`。 | 两次均成功，任务实际处理人取当前管理员；A库存依次为 `1010000`、`1011000`。管理员也能从库存行“补货”创建任务。 |
| A11 | 尝试删除已经有补货引用的 A，再尝试删除已经有订单引用的 P。 | 两者均被拒绝；A、P及原有订单/补货数据保留。P可下架，不能以物理删除破坏历史。 |
| A12 | 对空且已取消的 O4 点“删除空单”；再尝试删除仍保留明细的 O5。 | O4删除成功；O5因非空被拒绝。已支付/已退款订单不允许删除，可用第7节直接接口补验。 |
| A13 | “退款账本”分别对 O1、O2 点“模拟结算 → 确认提交”。 | 两笔从“待模拟结算”变为“模拟结算完成”；仍分别为 `18.00` 和 `15.00`，不再扣顾客Token。 |
| A14 | 用第7节方法重复结算 O1，并查询退款账本结果。 | 返回原结果，不产生第二笔退款；后端保存服务端生成的 `SIM-<订单编号>`。界面输入的编号不改变这一服务端规则。 |
| A15 | 将 P、Q 下架；退出为游客，再搜索名称，随后管理员登录恢复在售。 | 游客看不到下架商品；管理员仍可查询和恢复；历史订单详情与金额不变。 |

“模拟结算完成”只表示本地账本登记，不代表外部支付渠道已向顾客转账。保留本轮订单、调用、退款及补货记录，不通过清库伪造恢复初始状态。

### 7. 手动检查隐藏按钮后的接口权限

在应用页面打开浏览器开发者工具的 Console，输入下列函数。它只使用当前浏览器登录会话和CSRF，不要在控制台打印Cookie、密码或会话令牌。

```javascript
async function checkApi(path, method = 'GET', payload = {}) {
  const session = await fetch('/api/v1/auth/session').then(r => r.json());
  if (session.code !== 'OK') throw new Error(session.message);
  const options = {
    method,
    headers: {'Content-Type': 'application/json', 'X-CSRF-Token': session.data.csrf}
  };
  if (method !== 'GET') options.body = JSON.stringify(payload);
  const response = await fetch('/api/v1' + path, options);
  const body = await response.json();
  console.table([{
    status: response.status, code: body.code,
    message: body.message, request_id: body.request_id
  }]);
  return body.data;
}
```

下表中的 `<O1>`、`<O4>`、`<A>`、`<P>` 必须替换为本轮记录的数字，不能原样粘贴。只在对应步骤之后执行成功/重复请求，避免提前改变后续状态。

| 身份与时点 | 控制台示例 | 预期 |
|---|---|---|
| 游客 | `await checkApi('/orders')` | 401，未登录 |
| 顾客 | `await checkApi('/inventory')` | 403，无库存权限 |
| web_other | `await checkApi('/orders/<O1>')` | 403，不能查看其他顾客订单 |
| web_other | `await checkApi('/orders/<O1>/pay', 'POST')` | 403，不改变O1 |
| web_other | `await checkApi('/orders/<O1>/refund', 'POST')` | 403，不增加退款记录 |
| 顾客，C11后 | `await checkApi('/orders/<O1>/pay', 'POST')` | 409，不能重复充值 |
| 顾客，C15后 | `await checkApi('/orders/<O1>/refund', 'POST')` | 200，返回原退款结果 |
| 顾客，C13后 | `await checkApi('/usage')` | 200，核对对应调用的account_id和上游消耗字段 |
| 店员 | `await checkApi('/products', 'POST', {})` | 403，无商品维护权限 |
| 店员 | `await checkApi('/accounts/<A>', 'PUT', {})` | 403，无账号维护权限 |
| 店员 | `await checkApi('/accounts/<A>', 'DELETE')` | 403，无账号删除权限 |
| 店员，O4删除前 | `await checkApi('/orders/<O4>', 'DELETE')` | 403，无订单物理删除权限 |
| 店员 | `await checkApi('/orders/<O1>/settle', 'POST')` | 403，无结算权限 |
| 店员，T1已完成 | `await checkApi('/restocks/<T1>/complete', 'POST', {actual_amount:'8000'})` | 409，不能重复增加库存 |
| 管理员，A14 | `await checkApi('/orders/<O1>/settle', 'POST')` | 200，结算幂等 |
| 管理员 | `await checkApi('/orders/<O1>', 'DELETE')` | 409，不能删除已完成订单 |
| 管理员 | `await checkApi('/orders', 'POST', {items:[{product_id:<P>,quantity:1}]})` | 403，员工不能冒充顾客下单 |
| 管理员 | `await checkApi('/usage', 'POST', {product_id:<P>,tokens_used:'1'})` | 403，员工不能冒充顾客消费 |

补验CSRF时，在当前登录页面单独执行 `fetch('/api/v1/orders', {method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).then(async r => ({status:r.status,body:await r.json()}))`，预期403，不创建订单。非法输入、业务失败和越权响应都应保持统一JSON结构，包含请求编号；不得出现SQL语句、堆栈或连接路径。

可再在商品搜索输入 `'; DROP TABLE Users;--`，应作为普通搜索文本处理，页面仍能清空搜索后正常查询；不要在数据库客户端执行此文本。关闭弹窗、刷新页面以及退出后重新登录，都不应让已保存的交易消失。

### 8. 全职责覆盖与结束核对

| 已实现操作 | 人工步骤 |
|---|---|
| 登录、登录失败、退出与身份切换 | G3/G4、各阶段换身份 |
| products.list / save / delete | G1/G2、A1～A4、S1、A11/A15 |
| orders.list / get / create | C1～C10、C19/C20、S2、A8 |
| orders.item_add / item_set / item_delete | C2～C7、C8 |
| orders.pay / cancel / delete | C9/C11/C12、S3、A9/A12 |
| usage.list / create 与 balances.list | C13/C14/C18/C19、S2、A8 |
| inventory.list 与 accounts.save / delete | A5～A7、S4、A8/A11 |
| restocks.list / create / complete | S4～S6、A10 |
| refunds.list / request / settle | C15～C20、S2、A13/A14 |

- [ ] 四种角色入口、正确/错误登录、退出、搜索、空状态已核对；有足够数据时再核对翻页。
- [ ] 顾客的草稿明细增改删、同商品合并、价格快照、取消、支付和消费已核对。
- [ ] 未消费退款、部分消费退款、全部消费拒退、重复支付拒绝和退款幂等已核对。
- [ ] 第二顾客的数据隔离，以及店员/管理员的跨顾客只读查询已核对。
- [ ] 店员创建/完成补货、管理员继承这些职责，以及必要删除的成功/拒绝路径已核对。
- [ ] 页面隐藏按钮与直接API权限一致；CSRF、非法输入和失败反馈均已核对。
- [ ] 截图、对象编号、操作前后值及失败请求编号已记录；普通Windows账户的部署验收按应用手册另外记录，不能由本流程代替。
