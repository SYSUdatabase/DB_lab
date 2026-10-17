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
