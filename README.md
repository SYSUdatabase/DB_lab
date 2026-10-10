# API Token 中转站数据库实验 v0.1

本仓库交付数据库课程第 1～4 周成果：经营场景、关系模式、建库与样例数据、CRUD、多表查询、统计视图、完整性与最小权限。正式运行入口为 `sql/` 与 `tools/run_v01.ps1`。

2026-10-02 已修复样例数据时间顺序、历史负余额、过期账号调用和证据验收问题，在两个新空库完成真实复现。结果见 [验收证据](result/README.md)，设计与实验总结见 [阶段报告](report/stage_report.md)。

## 业务范围

用户购买 OpenAI、Claude、Gemini 的 Token 套餐；订单明细保存价格和 Token 快照。支付形成按用户/provider 管理的余额，调用扣减余额及上游账号额度，库存流水保留变动，日/周/月汇总用于经营分析。

进入数据库：用户、员工、角色、商品、订单与明细、上游账号、库存与流水、Token 余额与调用、使用汇总、补货任务及异常。

暂不进入数据库：明文密码、真实 API Key、Prompt 和完整请求/响应、支付平台详细流水、设备/IP、图片和非核心日志。样例凭据均为教学占位符。真实登录、支付/退款、补货事务、会员写操作与并发控制留到后续阶段。

销售只计算 `Orders.status='paid'`，金额采用订单明细下单快照。样例 refunded 订单已净冲销，不为当前余额形成充值。

## 业务流程

流程中的规则均由 `sql/verify.sql`（VFY）、`sql/role.sql`（R）、`sql/constraint.sql`（C）和 `sql/query.sql`（Q）逐条验收，编号见 [当前验收](#当前验收)。

### 会员：购买与使用 Token

1. **注册/登录**：写入 `Users`，记录 `created_at`。此后所有订单与调用都必须晚于该时间（VFY12）。
2. **浏览商品**：读取 `v_ProductCatalog`，只暴露在售商品的价格、Token 档位和上游折算量。
3. **选购下单**：写入 `Orders`（`status='pending'`，`paid_at` 必须为 NULL）与 `OrderDetails`（保存商品、单价、Token 数快照）。
4. **支付**：状态改为 `paid` 并写入 `paid_at`。`CK_Orders_payment_time`（在 `sql/constraint.sql` 中补充创建）强制 paid/refunded 必须有 `paid_at` 且不早于 `created_at`，pending/cancelled 必须为 NULL。
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

余额按 provider 分账，充值只认 `paid_at`、只计 `paid` 订单。最终余额非负不足以证明过程正确，因此 `sql/verify.sql` 逐事件回放历史余额。同秒事件先到账后消费，保证任何时刻余额非负。

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
- [SQL 说明](sql/README.md)、[阶段报告](report/stage_report.md)、[角色流程](report/role_workflow.md)
- [结果证据](result/README.md)、[复现说明](docs/reproduction.md)
- [ai使用文档（第四周提交正文）](docs/ai使用文档.md)、[AI 详细日志](docs/ai_usage_log.md)、[组内分工](docs/team_division.md)、[修复记录](ROADMAP.md)
- [历史材料与迁移映射](archive/README.md)


## 第二阶段：第五周 ER 模型（2026-10-10）

第五周基于第一阶段 v0.1 **逆向分析** 14 张表、17 条 FK，明确实体标识、联系基数和参与约束，暂不修改既有表结构。正式交付入口是 [第五周 ER 设计审查](report/week5/README.md)，包含 [可编辑 ER 图](report/week5/er_diagram.mmd)、[SVG 图](report/week5/er_diagram.svg)、[数据字典](report/week5/data_dictionary.md)、[业务规则映射](report/week5/business_rules_mapping.md)、[v0.1 问题与保留项](report/week5/v01_issues.md)、[设计说明和真实只读验证](report/week5/design_validation.md)。

本周在现存 `TokenHubDB_v01_A` 上只读核验了 100 订单、184 明细、68 个多明细订单；0 张无明细订单并不意味着数据库外码强制“一单至少一明细”。散客定义、同商品重复明细、账号是否必有库存和自动补货创建人仍待团队确认。第六周才研究规范化和结构迁移；v0.1 运行入口仍保持不变。
