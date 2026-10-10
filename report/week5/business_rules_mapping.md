# 第五周业务规则与 ER 联系映射清单（v0.1）

**阅读约定**：一条规则以“父表→子表”描述。`父→子` 表示任一父行允许关联多少子行；`子→父` 表示任一子行允许关联多少父行。数值是 **min..max**，不是样例数据统计。`0..*` 不等于已经有 N 行。`1..1` 通常来自子 FK 的 NOT NULL + 引用完整性，`0..1` 来自可空 FK，`0..*`/ `0..1` 来自父侧是否限制子引用唯一。表中写的是**当前 DDL 能保证的物理参与性**。

## A. 17 条真实外码（与源 ER 图逐条对应）

| ID | 父表 → 子表（联系/角色） | 父→子 | 子→父 | 子表 FK 列 / 实际约束名 | 当前实现及适用条件 |
|---|---|---|---|---|---|
| F01 | `Roles → Employees`（分配应用角色） | 0..* | 1..1 | `Employees.role_id` / `FK_Employees_Roles` | 非空 FK；角色可暂时没有员工 |
| F02 | `Users → Orders`（创建订单） | 0..* | 1..1 | `Orders.user_id` / `FK_Orders_Users` | 非空 FK；只支持关联已存在用户 |
| F03 | `Users → TokenBalances`（持有 provider 余额） | 0..* | 1..1 | `TokenBalances.user_id` / `FK_TokenBalances_Users` | 非空 FK；`UQ_TokenBalances_user_provider` 限制每 provider 最多一行 |
| F04 | `Users → TokenUsageLogs`（发起 API 调用） | 0..* | 1..1 | `TokenUsageLogs.user_id` / `FK_TokenUsageLogs_Users` | 非空 FK；注册前不得调用是另一个跨表/时间规则 |
| F05 | `Users → UsageSummary`（消费汇总） | 0..* | 1..1 | `UsageSummary.user_id` / `FK_UsageSummary_Users` | 非空 FK；汇总来源与粒度另行核验 |
| F06 | `Orders → OrderDetails`（包含明细） | **0..*（物理）** | 1..1 | `OrderDetails.order_id` / `FK_OrderDetails_Orders` | 非空 FK；**业务期望父→子至少 1..*，现有 FK 无法保证** |
| F07 | `Products → OrderDetails`（被购买） | 0..* | 1..1 | `OrderDetails.product_id` / `FK_OrderDetails_Products` | 非空 FK；`UQ_OrderDetails_order_product` 禁止同单同商品重复明细行 |
| F08 | `Products → TokenUsageLogs`（套餐被调用） | 0..* | 1..1 | `TokenUsageLogs.product_id` / `FK_TokenUsageLogs_Products` | 非空 FK；一次调用对应一套餐 |
| F09 | `Products → UsageSummary`（按套餐汇总） | 0..* | 1..1 | `UsageSummary.product_id` / `FK_UsageSummary_Products` | 非空 FK；与用户、周期一起组成汇总粒度 |
| F10 | `UpstreamAccount → Inventory`（剩余额度快照） | 0..1 | 1..1 | `Inventory.account_id` / `FK_Inventory_UpstreamAccount` | 非空 FK + `UQ_Inventory_account`；账号**可无库存行**但库存不能无账号 |
| F11 | `UpstreamAccount → InventoryLog`（额度变化） | 0..* | 1..1 | `InventoryLog.account_id` / `FK_InventoryLog_Account` | 非空 FK；操作人可选，流水金额必须非零 |
| F12 | `UpstreamAccount → TokenUsageLogs`（实际供应） | 0..* | 1..1 | `TokenUsageLogs.account_id` / `FK_TokenUsageLogs_Account` | 非空 FK；provider/有效期跨表条件靠额外验证 |
| F13 | `UpstreamAccount → RestockTask`（补货对象） | 0..* | 1..1 | `RestockTask.account_id` / `FK_RestockTask_Account` | 非空 FK；一账号可有多次任务 |
| F14 | `Employees → InventoryLog`（操作人） | 0..* | **0..1** | `InventoryLog.operator_id` / `FK_InventoryLog_Operator` | 可空 FK；NULL 表示无指定人工操作人，不能自动推出合法系统操作人 |
| F15 | `Employees → RestockTask`（创建人） | 0..* | **1..1** | `RestockTask.created_by` / `FK_RestockTask_CreatedBy` | 非空 FK；自动创建任务是否有系统员工需业务确认 |
| F16 | `Employees → RestockTask`（指派人） | 0..* | **0..1** | `RestockTask.assigned_to` / `FK_RestockTask_AssignedTo` | 可空 FK；未分配可为 NULL |
| F17 | `Employees → ExceptionLog`（处理人） | 0..* | **0..1** | `ExceptionLog.handled_by` / `FK_ExceptionLog_HandledBy` | 可空 FK；尚未处理时可为空 |

**图例与特殊联系**：正式导出图直接标出 `1..1`、`0..1`、`0..*`、`1..*`。每条虚线对应一个真实 FK 且不参与子表的主码，因此是**非标识性联系**；线型不表示字段是否可空，须以参与基数和 DDL 为准。可编辑 `er_diagram.mmd` 必须使用 Mermaid 的关系语法，`..` 是非标识性关系。双外码角色、关联实体、派生与多值属性详见 [特殊 ER 要素](special_er_features.md)。图中不将业务愿望画成既有 DDL 保证。

## B. 业务上的多对多与逻辑联系（**不是额外 17 条 FK**）

| 规则 | 两端的业务基数与参与条件 | 映射/依据 | 现状实现层 |
|---|---|---|---|
| **订单与套餐** | 一张有效订单业务上有 1..* 条明细；一件套餐可能在 0..* 条明细被购买；一条明细必选 1 个订单和 1 个商品 | `Orders ↔ OrderDetails ↔ Products`；两个实际非空 FK | 子端 FK + `UQ_OrderDetails_order_product`；**订单至少一条明细目前未即时约束**；`verify.sql` 检查样例对账 |
| **会员与 provider 余额** | 一用户可有 0..* 个 provider 余额条目；每个条目属于 1 用户、一个 provider 值 | `TokenBalances.user_id` 实际 FK；`model_provider` 为枚举字符，不是 provider 实体 FK | `UQ_TokenBalances_user_provider` + CHECK；跨表到账与用量由回归校验 |
| **套餐与上游账号** | 按 provider 等业务规则选择服务来源，多套餐可能使用多账号，关系由一次调用事件落实；无直接套餐—账号 FK | `TokenUsageLogs.product_id`、`account_id` 两条 FK | 数据库能保证两行各自存在；**不能通过两条 FK 保证 provider 匹配**；`verify.sql` VFY12 检查 |
| **补货任务与库存流水** | 任务可能对应 0..* 条流水；某流水逻辑上可能指向 0..1 个任务，取决于 `reference_type` | `InventoryLog.reference_type/reference_id`，不是真实 FK | 仅有枚举 CHECK；目标存在性和对应关系尚需应用或迁移方案 |
| **异常与订单或其他对象** | 异常可关联 0..1 个业务对象（类型决定对象）；业务对象可有 0..* 次异常 | `ExceptionLog.related_table/related_id`，无真实 FK | 字符串/编号弱引用，未由 DB 强制存在性 |
| **会员 vs 无账户散客** | 业务若允许散客无账户下单，订单对用户应允许 0..1（散客）或 1..1（会员）且有类型约束 | 当前 `Orders.user_id NOT NULL` + FK | 仅实现订单 1..1 用户；“无账户散客”目前无法直接落单；需先确认业务口径 |

## C. 完整性规则 / 谁在落实

| ID | 业务规则及适用条件 | v0.1 保证方式 | 验证位置与已知边界 |
|---|---|---|---|
| B01 | 明细 `quantity > 0`、`unit_price > 0`、`total_tokens` 正确 | CHECK + 第四周 `CK_OrderDetails_subtotal_formula`、`CK_OrderDetails_tokens_formula` | `sql/constraint.sql` C08/C09；只保证同一行公式 |
| B02 | `paid/refunded` 订单有付款时间，`pending/cancelled` 没付款时间 | `CK_Orders_payment_time` | `sql/constraint.sql` C10；不等于真正支付事务已实现 |
| B03 | **每张订单必须有至少一条明细** | 当前未用即时结构约束保证；样例 0 个无明细 | `readonly_validation.log` 的 `orders_without_details = 0`，只是样例状态 |
| B04 | 订单总额与明细小计之和、总 Token 与明细之和一致 | 跨表对账（不是 FK/CHECK） | `sql/verify.sql` 的 VFY 对账；当前现场 `header_detail_mismatch=0` |
| B05 | 上游账号与库存配额：`current_quota = total_quota - used_quota` | 分别的非负 CHECK + 跨表对账 | `sql/verify.sql`；现场 `inventory_quota_mismatches=0`，不能保证每次独立写入立刻一致 |
| B06 | 每账号要求必有一库存快照 | DB 仅保证账号→库存 0..1；是否要求 1..1 待确认 | 当前现场 `accounts_without_inventory=0`；不能推出结构强制 |
| B07 | 调用账号的 `provider` 必须与产品 provider 匹配且时间有效 | 目前三个非空 FK + 时间/匹配回归验证 | `sql/verify.sql` VFY12；现场 `provider_mismatched_usage=0`；未以复合 FK 即时强制 |
| B08 | 历史任一事件时刻会员余额不得为负；充值按 `paid_at` 后可消费 | 余额行 `remaining_tokens >= 0` CHECK + 历史逐事件检查 | `sql/verify.sql` VFY13；存量余额非负不等于历史任意时刻非负 |
| B09 | 补货额度、任务状态、库存流水 change_amount 的域合法 | CHECK；实际引用弱 FK 需要额外关联校验 | `sql/01_create_tables.sql`、`sql/constraint.sql` |
| B10 | 查询低库存（额度小于安全阈值） | `Inventory` 联 `UpstreamAccount`、库存视图 | 本周只读记录为 Gemini 账号 2 个；该口径**不要求账号当前可用** |
| B11 | 员工/会员/游客的数据库读写权限不同 | SQL Server DATABASE ROLE / VIEW，与 ER 的 Roles 表不同 | `sql/role.sql` 和 `sql/verify.sql`；角色应用层的关联不等同 SQL 授权 |

## D. 业务约束与结构约束的差异归纳

- **DDL 当前可保证**：每条非空 FK 都有父行；可空 FK 可以没父行；UNIQUE 约束候选码；CHECK 限制同表字段；`Inventory.account_id` 最多一行。
- **目前靠回归/业务流程检查**：订单汇总、库存对账、provider 匹配、逐事件历史余额、上游账号到期边界；是否有实时事务强制应在第七至九周落实并验收。
- **未被现有结构表达或应与小组确认**：订单至少有一条明细、无账户散客、自动建补货任务创建人、多态弱引用、一单同商品可否重复明细行。
- 第五周仅识别和说明，不运行 `ALTER/DROP`；第六周再用迁移脚本做结构调整。实际取证：`../../result/week5/readonly_validation.log`。
