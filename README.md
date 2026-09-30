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
| 店员 `hub_staff` | 查看经营数据、处理待处理订单 | 读取经营视图；仅能通过 `v_StaffOrderQueue.status` 切换 pending/cancelled |
| 会员 `hub_customer` | 浏览商品、查看本人订单/余额/用量 | 仅在售商品和个人视图；不能直接读取订单、余额、上游账号基表 |
| 游客 `hub_guest` | 未登录浏览 | 仅可读取在售商品目录 |

`dbo.Roles` 是应用层角色数据；`hub_manager` 等 SQL Server DATABASE ROLE 才是本周真正执行权限控制的数据库角色，两者用途不同。

## 3. 核心业务流程

```text
浏览商品
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

第四周另外创建 9 个视图：4 个经营统计视图和 5 个权限用途视图。完整表字段、主码、候选码和外码见 [第二周交付](week1%20%26%202/week2_deliverables_v2.md)，实际 DDL 以 [`sql/01_create_tables.sql`](sql/01_create_tables.sql) 为准。

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
→ query.sql
→ view.sql
→ constraint.sql
→ role.sql
→ verify.sql
→ signature.sql
```

其中 00～03 来自第三周数据基线，经 `tools/prepare_v01.ps1` 转换为可指定数据库名的 SQLCMD 版本。正常复现直接使用已经提交的根目录 `sql/`，只有更新第三周基线时才重新运行转换脚本。

## 8. 一键复现

从仓库根目录执行：

```powershell
powershell -NoProfile -File .\tools\run_v01.ps1 `
  -DatabaseName TokenHubDB_v01_A `
  -RunLabel run_A
```

流水线使用 Windows 身份验证，不硬编码密码。目标数据库已存在时会拒绝覆盖，不自动删除已有库；任何未预期 SQL 错误都会因为 `sqlcmd -b` 返回非零退出码并停止。

复现完成后查看：

- `result/run_A/console.log`：流水线 PASS 信息
- `result/run_A/query.sql.log`：关键查询结果
- `result/run_A/constraint.sql.log`：合法/非法完整性用例
- `result/run_A/role.sql.log`：正常访问与越权访问结果
- `result/run_A/verify.sql.log`：综合断言
- `result/run_A/signature.txt`：14 张业务表内容签名

第二次使用不同空库运行，并比较两个 `signature.txt`，即可证明业务数据可重复构建。项目已经实际用 `TokenHubDB_v01_A` 和 `TokenHubDB_v01_B` 完成该验证。

## 9. 结果与报告

- 结果证据索引：[result/README.md](result/README.md)
- 真实结果截图：[result/screenshots/](result/screenshots/)
- 阶段报告：[week4/stage_report.md](week4/stage_report.md)
- AI 使用记录：[week4/ai_usage_log.md](week4/ai_usage_log.md)
- 分工记录：[week4/team_division.md](week4/team_division.md)
- 课堂演示指南：[DEMO_GUIDE.md](DEMO_GUIDE.md)

## 10. 各周原始材料入口

- 第 1 周：[week1_deliverables.md](week1%20%26%202/week1_deliverables.md)
- 第 2 周：[week2_deliverables_v2.md](week1%20%26%202/week2_deliverables_v2.md)
- 第 3 周：[week3_deliverables.md](week3/week3_deliverables.md)；历史 SQL 位于 `week3/sql/`
- 第 4 周：[week4_deliverables.md](week4/week4_deliverables.md)
- 第一阶段完整报告：[stage_report.md](week4/stage_report.md)

## 11. 当前实测结论

2026-09-30 已在 `localhost\SQLEXPRESS` 实际完成两个全新数据库的完整流水线：

- 14 张业务表、9 个视图、4 个数据库角色、5 个演示用户均存在。
- 已支付订单 85 个，销售额 4228.90，售出 Token 92950000。
- Q01～Q08、C01～C11、R01～R13、VFY01～VFY11 均通过。
- `TokenHubDB_v01_A` 与 `TokenHubDB_v01_B` 的 14 张业务表内容 SHA-256 签名完全一致。
- 在 A 库重复执行视图、约束、角色和综合验收后，基础数据签名仍未变化。

这些结论均可追溯到 `result/` 的原始日志和截图证据。
