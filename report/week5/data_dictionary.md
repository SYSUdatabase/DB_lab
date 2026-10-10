# 第五周数据字典与实体标识（v0.1）

> 来源：`sql/01_create_tables.sql`（14 张实体表）、`sql/constraint.sql`（第四周后加 CHECK）、当前 `TokenHubDB_v01_A` 的只读目录查询。此文记录的是**建模事实**，不是结构修改提案。字段命名保留 DDL 原样，不读取凭证值。

## 1. 实体与行粒度

| 实体（表名） | 为什么独立保存 / 一行代表什么 | 主码 PK | 候选码（DDL 中 UNIQUE） | 外码 FK |
|---|---|---|---|---|
| `Roles` | 应用层员工角色定义；一行是一类角色及授权描述 | `role_id` | `role_name` | — |
| `Users` | 平台注册用户/会员；一行是一个用户账户 | `user_id` | `username`，`email` | — |
| `Products` | 出售的 Token 套餐；一行是一种供应商及 Token 档位 | `product_id` | `name`；(`model_provider`,`token_amount`) | — |
| `UpstreamAccount` | 真正供应 Token 的上游账号；一行是一个上游账号 | `account_id` | (`provider`,`account_name`) | — |
| `Inventory` | 上游账号的当前剩余额度；一行是某账号的一条库存快照 | `inventory_id` | `account_id` | `account_id → UpstreamAccount.account_id` |
| `Employees` | 处理运营工作的员工；一行是一个员工及其应用角色 | `employee_id` | `account` | `role_id → Roles.role_id` |
| `Orders` | 会员购买交易；一行是一张订单头 | `order_id` | 无其他 UNIQUE | `user_id → Users.user_id` |
| `OrderDetails` | 订单与商品的关联实体；一行是一条商品购买明细及成交快照 | `detail_id` | (`order_id`,`product_id`) | `order_id → Orders.order_id`；`product_id → Products.product_id` |
| `InventoryLog` | 上游配额变更留痕；一行是一次额度变化 | `log_id` | 无其他 UNIQUE | `account_id → UpstreamAccount.account_id`；`operator_id → Employees.employee_id`（可空） |
| `TokenBalances` | 会员按 provider 独立结算；一行是一个会员在一个 provider 下的余额 | `balance_id` | (`user_id`,`model_provider`) | `user_id → Users.user_id` |
| `TokenUsageLogs` | 一次 API 调用及消费；一行是一条真实调用事件 | `log_id` | 无其他 UNIQUE | `user_id → Users.user_id`；`product_id → Products.product_id`；`account_id → UpstreamAccount.account_id` |
| `UsageSummary` | 按用户、商品、周期统计的汇总；一行是一个用户某套餐某周期起点的统计 | `summary_id` | (`user_id`,`product_id`,`period_type`,`period_start`) | `user_id → Users.user_id`；`product_id → Products.product_id` |
| `RestockTask` | 上游额度补货流程；一行是一次补货任务 | `task_id` | 无其他 UNIQUE | `account_id → UpstreamAccount.account_id`；`created_by → Employees.employee_id`；`assigned_to → Employees.employee_id`（可空） |
| `ExceptionLog` | 异常事件及处理；一行是一条异常及处理状态 | `exception_id` | 无其他 UNIQUE | `handled_by → Employees.employee_id`（可空） |

**候选码区分**：PK 是选定的主标识；其余 UNIQUE 且非空的列/组合是在当前 DDL 下可用的候选标识。复合 UNIQUE 只保证**整个元组**唯一，并不表示每个成员单独唯一。图上复合键各成员标 `UK`，必须结合本表理解。身份流水表的 `log_id` 不是跨表业务关联的通用键。

## 2. 属性清单（完整 DDL 列名；不含任何字段取值）

- **Roles**：`role_id`, `role_name`, `description`（NULL）, `permissions`（NULL，JSON）；其余 NOT NULL。CHECK 限制角色名、JSON 合法性。
- **Users**：`user_id`, `username`, `password_hash`, `email`, `phone`（NULL）, `status`, `created_at`, `updated_at`；其余 NOT NULL。`status` 有 DEFAULT/CHECK。凭证哈希仅作为结构字段列出，不读取或展示内容。
- **Products**：`product_id`, `name`, `description`（NULL）, `price`, `model_provider`, `token_amount`, `required_upstream_tokens`, `status`, `created_at`；其余 NOT NULL。价格与数量均有 CHECK。
- **UpstreamAccount**：`account_id`, `provider`, `account_name`, `api_key`（敏感列，仅描述模式）, `total_quota`, `used_quota`, `safety_threshold`, `status`, `expires_at`（NULL）, `created_at`, `updated_at`；其余 NOT NULL。额度界限有 CHECK。
- **Inventory**：`inventory_id`, `account_id`, `current_quota`, `last_updated_at`；均 NOT NULL。`account_id` UNIQUE 使同一账号最多一行库存。
- **Employees**：`employee_id`, `name`, `role_id`, `account`, `password_hash`, `hire_date`, `status`；均 NOT NULL。
- **Orders**：`order_id`, `user_id`, `total_amount`, `total_tokens`, `status`, `created_at`, `paid_at`（NULL）；其余 NOT NULL。支付状态和时间由 `CK_Orders_payment_time` 限制。
- **OrderDetails**：`detail_id`, `order_id`, `product_id`, `quantity`, `unit_price`, `subtotal`, `tokens_per_unit`, `total_tokens`；均 NOT NULL。金额及 Token 小计由公式 CHECK 限制。
- **InventoryLog**：`log_id`, `account_id`, `change_type`, `change_amount`, `reference_id`（NULL）, `reference_type`（NULL）, `reason`（NULL）, `operator_id`（NULL）, `created_at`；其他 NOT NULL。`reference_id` 不是 FK。
- **TokenBalances**：`balance_id`, `user_id`, `model_provider`, `remaining_tokens`, `updated_at`；均 NOT NULL。`model_provider` 有 CHECK 但不是 FK。
- **TokenUsageLogs**：`log_id`, `user_id`, `product_id`, `account_id`, `tokens_used`, `upstream_tokens_consumed`, `api_endpoint`（NULL）, `used_at`；其余 NOT NULL。
- **UsageSummary**：`summary_id`, `user_id`, `product_id`, `period_type`, `period_start`, `period_end`, `total_tokens_used`, `total_upstream_consumed`, `request_count`, `last_updated_at`；均 NOT NULL。周期范围和非负聚合有 CHECK。
- **RestockTask**：`task_id`, `account_id`, `trigger_reason`, `restock_method`, `target_amount`, `actual_amount`（NULL）, `created_by`, `assigned_to`（NULL）, `status`, `created_at`, `completed_at`（NULL）, `notes`（NULL）；其他 NOT NULL。
- **ExceptionLog**：`exception_id`, `exception_type`, `related_table`（NULL）, `related_id`（NULL）, `error_message`, `error_detail`（NULL）, `occurred_at`, `handled_by`（NULL）, `handle_result`（NULL）, `handle_notes`（NULL）, `handled_at`（NULL）；其他 NOT NULL。`related_table/related_id` 不受一般 FK 保护。

## 3. 实体类型与重要的设计区别

| 类型 | 代表 | 说明 |
|---|---|---|
| 独立实体 | Users、Products、Employees、UpstreamAccount、Roles | 即使暂无交易也应能独立保存；Roles 是应用角色数据，不等于 SQL Server 的数据库 ROLE |
| 交易与关联实体 | Orders、OrderDetails | Orders 是交易头；OrderDetails 用两条非空 FK 表达“订单—商品”业务多对多，另有独立 `detail_id` 主码 |
| 依附状态/账户 | Inventory、TokenBalances | Inventory 依赖上游账号且一账号最多一库存行；TokenBalances 按会员 × provider 唯一 |
| 事件流水 | InventoryLog、TokenUsageLogs、ExceptionLog | 不可用当前快照替代历史；弱引用必须区别真实 FK |
| 派生汇总/任务 | UsageSummary、RestockTask | 业务粒度和状态信息需要单独维护，也会引入与原始事实的同步责任 |

## 4. 三个最易混淆的关系

1. `Products` 是卖给用户的套餐；`UpstreamAccount` 和 `Inventory` 是购买后实际使用的上游额度。两者**没有直接 FK**。`TokenUsageLogs` 才把某次调用使用的套餐与上游账号联系起来。
2. `Orders` 可以引用一个 `Users` 记录；`user_id NOT NULL` 意味着当前结构无法直接插入无注册用户记录的匿名订单。
3. `Roles.role_name` 只能表示现有应用层角色枚举；SQL Server `hub_manager/hub_staff/hub_customer/hub_guest` 是第四周另外创建的数据库授权主体，不能画成 `Roles` 表的子表。

## 5. 证据与校验边界

- DDL、候选码、NOT NULL 和 FK：`sql/01_create_tables.sql`；追加公式与支付 CHECK：`sql/constraint.sql`。
- 实际数据库：`result/week5/readonly_validation.sql`、`readonly_validation.log`，查询 `TokenHubDB_v01_A` 的结构计数为 14 表、17 FK、3 个追加 CHECK；各表定义仍以正式 DDL 为主要依据。
- 字典不包含任何凭证取值；敏感列只允许记录字段存在及其目的。
