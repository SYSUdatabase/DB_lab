# 第一阶段 v0.1 阶段报告

## 一、设计思路

### 1. 经营场景与业务流程

本项目模拟 API Token 中转站。平台向用户销售不同 AI provider 的 Token 套餐，用户支付后获得对应模型余额，之后通过平台调用 API；平台从上游账号额度中提供服务，并记录库存、库存流水、使用量、补货和异常。

核心闭环：

```text
浏览商品 → 创建订单 → 支付 → 增加用户 Token 余额
→ API 调用 → 扣减用户余额和上游库存
→ 记录调用日志/库存流水 → 统计汇总 → 低库存补货/异常处理
```

经营角色包括店长、店员、会员和游客。店长负责商品、库存、订单和经营分析；店员主要查看经营数据并处理待处理订单；会员只能访问商品和本人业务数据；游客只浏览在售商品。

销售统计统一只计算 `Orders.status='paid'`，历史销售额采用 `OrderDetails.subtotal` 的下单快照，不用当前商品价格重算历史订单。

### 2. 数据边界：哪些信息进入数据库，哪些暂不进入

进入数据库的信息包括：用户账户元数据、商品套餐、订单与明细、上游账号元数据、库存与库存流水、Token 余额、调用用量、日/周/月使用汇总、员工与角色、补货任务、异常处理结果。这些信息直接参与交易、额度控制、审计或经营分析。

暂不进入数据库的信息包括：用户密码明文、真实 API Key、Prompt 与完整 API 请求/响应、第三方支付详细流水、设备/IP、图片文件等。原因分别是安全、隐私、课程范围和存储成本。本项目只保存密码哈希；样例 API Key 使用 `DEMO_NOT_A_REAL_API_KEY_*` 明确占位符。

真实注册、支付、退款、充值、补货事务、并发控制和应用登录映射也暂不作为 v0.1 的完整业务事务实现，它们属于后续阶段。

### 3. 表设计、主码、候选码与外码

14 张表按“业务实体有独立身份、关系通过外键表达、天然唯一属性使用候选码”设计。核心键如下：

| 表 | 主码 | 主要候选码 | 主要外码 |
|---|---|---|---|
| Users | `user_id` | `username`、`email` | 无 |
| Products | `product_id` | `name`、(`model_provider`,`token_amount`) | 无 |
| UpstreamAccount | `account_id` | (`provider`,`account_name`) | 无 |
| Inventory | `inventory_id` | `account_id` | `account_id → UpstreamAccount` |
| InventoryLog | `log_id` | 无 | `account_id → UpstreamAccount`、`operator_id → Employees` |
| Orders | `order_id` | 无 | `user_id → Users` |
| OrderDetails | `detail_id` | (`order_id`,`product_id`) | `order_id → Orders`、`product_id → Products` |
| Employees | `employee_id` | `account` | `role_id → Roles` |
| Roles | `role_id` | `role_name` | 无 |
| TokenBalances | `balance_id` | (`user_id`,`model_provider`) | `user_id → Users` |
| TokenUsageLogs | `log_id` | 无 | `user_id → Users`、`product_id → Products`、`account_id → UpstreamAccount` |
| UsageSummary | `summary_id` | (`user_id`,`product_id`,`period_type`,`period_start`) | `user_id → Users`、`product_id → Products` |
| RestockTask | `task_id` | 无 | `account_id → UpstreamAccount`、`created_by/assigned_to → Employees` |
| ExceptionLog | `exception_id` | 无 | `handled_by → Employees` |

主码统一使用整数 ID，便于连接、索引和固定样例数据复现；候选码用于约束现实世界中应唯一的用户名、邮箱、员工账号、角色名和账号/套餐组合；外码保证订单、库存、使用记录等不能指向不存在的实体。

`Inventory` 关联 `UpstreamAccount` 而不是 `Products`，因为库存表示的是“上游账号还剩多少可用 Token”，产品只是销售层套餐。`Orders.total_tokens` 与 `OrderDetails.total_tokens` 是受控冗余：前者是订单汇总，后者是明细分项，`verify.sql` 会逐订单核对两者一致。

### 4. 完整性约束设计

本阶段同时使用实体完整性、参照完整性、域完整性和跨列业务约束：

- PK / UNIQUE：保证实体和候选码唯一。
- FK：保证订单、明细、库存、余额、调用日志等引用真实父实体。
- NOT NULL / DEFAULT：约束必要字段并给出稳定初始状态。
- CHECK：限制价格、数量、状态枚举、JSON 和非负额度等域。
- 第四周新增 3 个跨列 CHECK：`subtotal = quantity * unit_price`、`total_tokens = quantity * tokens_per_unit`、订单状态与 `paid_at` 一致。

订单头与明细汇总、上游账号与库存与流水属于跨表规则，普通 CHECK 无法直接可靠表达，因此通过 `verify.sql` 独立对账，并留给后续事务阶段维护。

### 5. 角色与权限划分及正反例

数据库层使用四个 SQL Server DATABASE ROLE，遵循最小权限原则：

| 角色 | 允许 | 明确禁止 |
|---|---|---|
| `hub_manager` | 14 张业务表 CRUD、经营视图 | CREATE TABLE、CONTROL、db_owner、sysadmin |
| `hub_staff` | 经营视图；仅更新 `v_StaffOrderQueue.status` | 直接改商品价格、任意基表 CRUD |
| `hub_customer` | 商品目录、本人订单/余额/用量 | 读取 Orders/TokenBalances/UpstreamAccount 等基表 |
| `hub_guest` | 在售商品目录 | 订单和个人数据 |

正例：R05 中店员可以在事务内将待处理订单 pending/cancelled 切换；R06/R07 中两个会员可以读取本人订单。反例：R04 中店员直接 UPDATE Products 返回错误 229；R09 中会员读取上游账号 API Key 被错误 229 拒绝；R13 中店员修改工作队列的 `user_id` 列被错误 230 拒绝。

会员隔离不依赖调用者可随意设置的变量，而是让数据库用户 `hub_user_1` / `hub_user_2` 通过 `USER_NAME()` 映射到业务用户 1 / 2，并且不向会员开放相关基表 SELECT。

## 二、实验过程

### 1. 第 1～2 周：业务与模式设计

第 1 周确定 API Token 中转站经营场景、四类角色、交易闭环和数据边界。第 2 周把业务实体转成 14 张关系表，定义字段类型、主码、候选码、外码、样例元组和关系说明。

### 2. 第 3 周：DDL、样例数据与 CRUD

第三周使用 SQL Server 2025 Express 落地 14 张表。`datagen.py` 使用固定随机种子生成业务相关样例数据，并自检订单金额、Token、余额、库存和外键关系。商品、库存和订单均完成 INSERT / SELECT / UPDATE / DELETE，演示写操作最终回滚，不污染基线。

### 3. 第 4 周：查询与视图

根目录 `sql/query.sql` 实现 Q01～Q08，覆盖 INNER JOIN、LEFT JOIN、GROUP BY、HAVING、NOT EXISTS 和按 provider 聚合。关键实测结果：订单明细 184 行；已支付商品销售总件数 191、销售额 4228.90；40 个会员中 14 个没有 paid 订单，13 个消费至少 100 元；调用记录共 3000 条，用户 Token 使用 6040100，上游消耗 7248120。

`sql/view.sql` 创建 9 个视图，其中四个核心经营视图为 `v_OrderDetail`、`v_ProductSales`、`v_MemberSpending`、`v_InventoryStatus`，行数分别为 184、10、40、8；另外 5 个视图服务于商品目录、会员隔离和店员工作队列权限。

### 4. 第 4 周：约束与权限

`constraint.sql` 先盘点现有约束，再新增 3 个跨列 CHECK，并通过 C01～C11 逐条执行正反例。只有错误号和必要的约束名符合预期才算 PASS，避免“只要报错就算成功”。

`role.sql` 创建 4 个数据库角色和 5 个 WITHOUT LOGIN 演示用户，逐项执行 R01～R13。实际验证访客、店员、会员和店长的允许/禁止操作，并确认会员相互隔离、没有固定高权限角色成员关系、public 没有业务对象授权。

### 5. 综合验收与空库复现

`verify.sql` 执行 VFY01～VFY11：逐表行数、订单与库存总量、视图行数、会员集合、商品/会员视图逐行比对、余额逐用户/provider 对账、UsageSummary 三种粒度逐键比对，以及零销量/低库存边界正例。

`tools/run_v01.ps1` 从空库按 `00 → 01 → 02 → 03 → query → view → constraint → role → verify → signature` 顺序执行。2026-09-30 实际构建 `TokenHubDB_v01_A` 与 `TokenHubDB_v01_B`，两次均成功；`signature.sql` 对 14 张表完整内容计算 SHA-256，A/B 逐表签名完全一致。

随后在 A 库重复执行 `view → constraint → role → verify`，再次签名仍与首次一致，证明第四周脚本可重复执行且不会改变基础业务数据。

### 6. 结果截图与证据

`result/screenshots/` 已保存 12 张真实 SQL Server 执行截图，覆盖成功建库、三组 CRUD、多表查询、销售/会员统计、四个核心视图、合法与非法完整性用例、不同角色权限、会员隔离和 A/B 双空库签名比较。每张截图都可追溯到 `result/evidence_sql/` 和 `result/evidence_logs/`。

主流水线原始日志保存在 `result/run_A/`、`result/run_B/` 与 `result/repeat_A/`。截图和日志分别证明“结果可视化”和“执行过程可追溯”，避免只依赖单一证据。

## 三、实验总结

第一阶段 v0.1 已经把业务需求、关系模式、DDL/CRUD、查询、视图、完整性和权限串成一套可以从空数据库重复执行的原型。相较于仅验证 SQL 能运行，本阶段进一步使用自动断言、预期错误号、逐行/逐键对账和双数据库内容签名来验证结果是否正确。

实际最终状态：14 张业务表、9 个视图、4 个数据库角色、5 个演示用户、3 个第四周新增跨列 CHECK；已支付订单 85 个，已支付销售额 4228.90，已支付 Token 92950000。Q01～Q08、C01～C11、R01～R13、VFY01～VFY11 均通过。

实验中两次实际执行反馈推动了人工修正：一是权限异常在 `XACT_ABORT ON` 事务中需要先 ROLLBACK 再 REVERT，否则出现 3930；二是 VFY06 原计划 CTE 后直接接 IF 在 SQL Server 中出现 156 语法错误，最终改为表变量与双向 EXCEPT。修正后完整流水线通过。

当前局限：数据是固定随机种子的合成数据，不代表真实客户或真实商业报价；库存状态使用固定样例快照，不是实时监控；WITHOUT LOGIN 用户与 `USER_NAME()` 映射用于课程权限演示，不是生产级身份体系；真实支付、退款、充值、补货事务和并发控制仍需后续阶段实现。

总体上，v0.1 已满足第一阶段从“业务设计”到“可复现数据库原型”的目标，并为下一阶段事务、存储过程、并发控制和应用接入保留了稳定数据基线。

## 四、证据位置

- 第一、二周设计：`week1 & 2/`
- 第三周历史实现：`week3/`
- 正式阶段 SQL：`sql/`
- 自动运行与签名：`result/run_A/`、`result/run_B/`、`result/repeat_A/`
- 结果截图：`result/screenshots/`
- 证据索引：`result/README.md`
