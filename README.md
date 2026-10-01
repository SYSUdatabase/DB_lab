# DB_lab - API Token 中转站数据库 v0.1

## 1. 项目范围

本项目是数据库实验课程第一阶段成果，模拟一个 API Token 中转站。用户购买不同 AI provider 的 Token 套餐，系统记录订单、余额和调用使用量；平台从上游 API 账号额度中提供服务，并记录库存、库存流水、补货任务和异常信息。

第一阶段第 1～4 周已经覆盖：经营场景与数据边界、14 表关系模式、SQL Server 建库与样例数据、CRUD、多表查询与聚合、统计视图、完整性约束、数据库角色权限、自动验收与双空库复现。

### 进入数据库的信息

- 用户账户元数据与状态，但只保存密码哈希，不保存明文密码。
- 商品套餐、订单、订单明细和 Token 余额。
- 上游账号元数据、库存、库存流水和补货任务。
- Token 调用用量、日/周/月汇总和异常处理记录。
- 员工、应用层角色以及本阶段用于演示的数据库角色权限。

### 暂不进入数据库的信息

- 用户密码明文和真实 API Key；教学数据中的 API Key 全部是占位符。
- Prompt、API 请求/响应正文，避免引入不必要的隐私数据。
- 第三方支付流水、设备/IP、图片文件和非核心运行日志。
- 真实注册、支付、退款、充值和并发事务流程，留到后续阶段实现。

## 2. 业务角色与权限边界

| 角色 | 业务职责 | v0.1 数据库权限 |
|---|---|---|
| 店长 `hub_manager` | 商品、库存、订单和经营管理 | 14 张业务表 CRUD 与经营视图读取；无 DDL、CONTROL、db_owner、sysadmin |
| 店员 `hub_staff` | 查看经营数据、处理待处理订单、联系客户 | 读取经营视图和客服视图 `v_CustomerService`；仅能通过 `v_StaffOrderQueue.status` 切换 pending/cancelled |
| 会员 `hub_customer` | 浏览商品、查看本人订单/余额/用量 | 仅在售商品和个人视图；不能直接读取订单、余额、上游账号基表 |
| 游客 `hub_guest` | 未登录浏览 | 仅可读取在售商品目录 |

`dbo.Roles` 是应用层角色数据；`hub_manager` 等 SQL Server DATABASE ROLE 才是本周真正执行权限控制的数据库角色，两者用途不同。会员的下单、支付和修改本人资料属于第三阶段存储过程（过程内校验 `USER_NAME()` 与目标用户一致），v0.1 只交付会员只读能力，详见 [`report/role_workflow.md`](report/role_workflow.md)。

## 3. 核心业务流程

以下流程覆盖了 4 个业务角色在 v0.1 的主要行为边界。

```text
游客（hub_guest）
  → 浏览在售商品目录 v_ProductCatalog

会员（hub_customer）
  → 浏览在售商品
  → 查看本人订单、余额、Token 用量（个人视图）
  → 下单、支付、修改本人资料（第三阶段存储过程实现）

店员（hub_staff）
  → 查看经营视图与待办队列 v_StaffOrderQueue
  → 通过队列视图更新 pending/cancelled 订单状态
  → 查看客服视图 v_CustomerService（不含 password_hash）

店长（hub_manager）
  → 商品、库存、订单、上游账号、补货任务等全业务管理（基于最小权限 CRUD）
  → 查看经营统计视图，处理异常和补货

系统流程
  → 创建订单 Orders / OrderDetails
  → 支付成功形成 TokenBalances
  → 用户调用 API 写入 TokenUsageLogs
  → 扣减 UpstreamAccount / Inventory
  → InventoryLog 保留变动流水
  → UsageSummary 按日/周/月汇总
  → 低库存进入 RestockTask
  → 异常进入 ExceptionLog
```

销售统计只计算 `Orders.status='paid'`；历史销售额使用订单明细中的下单价格快照，不用当前商品价格重算。

## 4. 数据库对象

14 张业务表按用途分组：

- 用户与内部人员：`Users`、`Roles`、`Employees`
- 商品与销售：`Products`、`Orders`、`OrderDetails`
- 上游供给：`UpstreamAccount`、`Inventory`、`InventoryLog`、`RestockTask`
- Token 使用：`TokenBalances`、`TokenUsageLogs`、`UsageSummary`
- 异常记录：`ExceptionLog`

第四周另外创建 10 个视图：4 个经营统计视图（`v_OrderDetail`、`v_ProductSales`、`v_MemberSpending`、`v_InventoryStatus`）和 6 个权限用途视图（商品目录、客服视图、会员隔离视图 3 个、店员工作队列）。实体关系图与键设计理由见 [`report/stage_report.md`](report/stage_report.md) 第 1 节第 3～4 小节，完整表字段、主码、候选码和外码见第二周交付（`week1 & 2/week2_deliverables_v2.md`，过程材料），实际 DDL 以 [`sql/01_create_tables.sql`](sql/01_create_tables.sql) 为准。

## 5. 第一至四周要求如何落到仓库

| 周次 | 要求 | 主要交付位置 |
|---|---|---|
| 第 1 周 | 场景、角色、流程、数据边界 | `week1 & 2/week1_deliverables.md`、本 README、阶段报告 |
| 第 2 周 | 关系模式、字段、主码/候选码/外码、样例元组 | `week1 & 2/week2_deliverables_v2.md`、`sql/01`、`sql/02` |
| 第 3 周 | 建库建表、样例数据、CRUD、非法值与一致性 | `sql/00`～`03`、`constraint.sql`、`verify.sql`，历史脚本保留在 `week3/` |
| 第 4 周 | 查询、视图、完整性、角色权限 | `query.sql`、`view.sql`、`constraint.sql`、`role.sql` |
| 阶段验收 | 从空库复现、断言、签名、证据 | `tools/run_v01.ps1`、`verify.sql`、`signature.sql`、`result/` |

SQL 目录总览见 [`sql/README.md`](sql/README.md)。

## 6. 环境要求

- Windows 10/11
- SQL Server 2025 Express
- SSMS
- ODBC `sqlcmd`
- PowerShell
- Python 3.11+；样例数据生成器只使用标准库

本机实际验证环境：SQL Server 2025 Express 17.0.1000.7、Python 3.12.6、`localhost\SQLEXPRESS`。

## 7. 正式 SQL 执行顺序

根目录 `sql/` 是 v0.1 正式执行入口：

```text
00_create_database.sql
→ 01_create_tables.sql
→ 02_insert_data.sql
→ 03_crud_demo.sql
→ view.sql
→ query.sql
→ constraint.sql
→ role.sql
→ verify.sql
→ signature.sql
```

视图先于查询执行，因为 Q09 直接引用 `v_InventoryStatus`。其中 00～03 来自第三周数据基线，经 `tools/prepare_v01.ps1` 转换为可指定数据库名的 SQLCMD 版本。正常复现直接使用已经提交的根目录 `sql/`，只有更新第三周基线时才重新运行转换脚本。

## 8. 一键复现

从仓库根目录执行：

```powershell
# 换一个未占用的库名和结果目录名
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_v01.ps1 `
  -DatabaseName TokenHubDB_v01_D `
  -RunLabel run_D
```

- `-ExecutionPolicy Bypass` 只作用于本次进程，用于绕过本机脚本执行策略限制；允许执行时可省略。
- **库名必须是新的。** 本项目当前已有 `TokenHubDB_v01_A`、`_B`、`_C` 三个库，直接用 `-DatabaseName TokenHubDB_v01_A` 会报 `TokenHubDB_v01_A already exists. Reproduction requires an empty database.` 并中止——脚本拒绝覆盖已有库。要重建同名库需显式加 `-DropExisting`（仅删除 `TokenHubDB_v01_*` 实验库），但删掉后该库就不能再作为截图证据来源了。
- `-RunLabel` 对应 `result/` 下的证据目录名，目录已存在时脚本拒绝覆盖，需换标签或先删目录，避免误删既有证据。
- 流水线使用 Windows 身份验证，不硬编码密码；任何未预期 SQL 错误都会因为 `sqlcmd -b` 返回非零退出码并停止。
- 失败原因见 `result/<RunLabel>/console.log` 与对应 `<脚本名>.log`；常见两类报错与处理方式见 [`DEMO_GUIDE.md`](DEMO_GUIDE.md) 第 2 节。

复现完成后查看（把 `run_D` 换成你实际用的 `-RunLabel`）：

- `result/run_D/console.log`：流水线 PASS 信息
- `result/run_D/query.sql.log`：关键查询结果
- `result/run_D/view.sql.log`：10 个视图结果
- `result/run_D/constraint.sql.log`：合法/非法完整性用例
- `result/run_D/role.sql.log`：正常访问与越权访问结果
- `result/run_D/verify.sql.log`：综合断言
- `result/run_D/signature.txt`：14 张业务表内容签名

用不同空库再跑一次并比较签名，即可证明业务数据可重复构建：

```powershell
Compare-Object `
  (Get-Content .\result\run_A\signature.txt) `
  (Get-Content .\result\run_B\signature.txt)
```

预期无输出。项目已实际用 `TokenHubDB_v01_A`、`TokenHubDB_v01_B`、`TokenHubDB_v01_C` 完成该验证，三者签名逐字节一致。上面示例中的 `run_A`/`run_B` 指已提交的三次复现结果；若你本次用的是 `run_D`，把它和另一个新跑出来的库对应的目录名代入即可。

## 9. 提交目录结构

提交物以根目录为准，`week1 & 2/`、`week3/`、`week4/` 为过程材料，仅供追溯。

```text
DB_lab/
├─ README.md               项目说明、数据边界、角色权限、复现方式
├─ DEMO_GUIDE.md          复现与验证说明（环境、命令、预期值、证据位置）
├─ ai_usage_log.md        第 1～4 周及 v0.1 修订的 AI 使用汇总
├─ team_division.md       全阶段分工与复核状态
├─ sql/                   正式 SQL 入口（00～03、view、query、constraint、role、verify、signature）
├─ tools/                 一键复现脚本、样例数据生成器、证据截图辅助脚本
├─ result/                执行日志、签名、截图、证据 SQL、第三周人工测试 PDF
└─ report/                阶段报告、角色流程图、ER 图、知识导图
```

- 阶段报告：[`report/stage_report.md`](report/stage_report.md)
- 角色—数据库操作流程：[`report/role_workflow.md`](report/role_workflow.md)
- 实体关系图与项目知识导图：[`report/stage_report.md`](report/stage_report.md) 第 1 节第 4、7 小节
- 结果证据索引：[`result/README.md`](result/README.md)
- 真实结果截图：[`result/screenshots/`](result/screenshots/README.md)
- 复现与验证说明：[`DEMO_GUIDE.md`](DEMO_GUIDE.md)

## 10. 各周原始材料入口

以下文件位于过程材料目录，**不随本提交包提供**，需要时从开发仓库的 `week1 & 2/`、`week3/`、`week4/` 查看。

- 第 1 周：`week1 & 2/week1_deliverables.md`
- 第 2 周：`week1 & 2/week2_deliverables_v2.md`
- 第 3 周：`week3/week3_deliverables.md`、`week3/sql/`（历史 SQL）；人工测试记录已随包提供：`result/第3周人工测试演示结果.pdf`
- 第 4 周：`week4/week4_deliverables.md`、`week4/week4_plan.md`（实施计划与修订记录）

过程材料中沉淀的设计结论已分别整理进本包：数据边界与角色见本 README 第 1～3 节，关系模式与键设计见 [`report/stage_report.md`](report/stage_report.md) 第 1 节与 `sql/01_create_tables.sql`，实验过程与修正记录见 [`report/stage_report.md`](report/stage_report.md) 第 2～3 节。

## 11. 当前实测结论

2026-10-01 已在 `localhost\SQLEXPRESS` 实际完成 `TokenHubDB_v01_A`、`TokenHubDB_v01_B`、`TokenHubDB_v01_C` 三个全新数据库的完整流水线：

- 14 张业务表、10 个视图、4 个数据库角色、5 个演示用户均存在。
- 已支付订单 85 个，销售额 4228.90，售出 Token 92950000。
- Q01～Q12、C01～C14、R01～R17、VFY01～VFY11 均通过。
- 三个数据库的 14 张业务表内容 SHA-256 签名逐字节一致；`sql/01_create_tables.sql` 与 `sql/02_insert_data.sql` 未改动，基础业务数据口径不变。
- 低于安全阈值的上游账号有 2 个，`v_InventoryStatus` 的 `stock_state='low'` 与基表推导结果一致。

这些结论均可追溯到 `result/run_A`、`result/run_B`、`result/run_C` 的原始日志，以及 `result/screenshots/` 中的 22 张 PNG（01～12 抓屏于 2026-09-30 基线脚本版本，13～22 抓屏于 2026-10-01，覆盖本轮新增的 Q09～Q12、C12～C14、R14～R17 与 VFY 全量验收）。
