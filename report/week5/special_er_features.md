# 第五周 ER 特殊要素审查（v0.1，区分概念模型与实际物理 DDL）

本文件是对《第五周任务讲解.docx》中“实体、属性、联系、基数、参与约束、联系通过中间实体实现”的细化核对。任务书**没有直接要求所有图都必须有弱实体或多值属性**；只有存在且业务规则明确时才应加专用表示。依据为 `sql/01_create_tables.sql`、`sql/constraint.sql`、`sql/verify.sql`，未读取密钥、密码哈希或其他敏感列取值，也未修改数据库。

## A. 特殊要素判定及是否应画出

| ER 要素 | 当前对象 / 事实 | 分类和图上处理 |
|---|---|---|
| **严格弱实体 / 标识性联系** | `OrderDetails` 有独立 `detail_id PK`；`Inventory` 有 `inventory_id PK`；`TokenBalances` 有 `balance_id PK`，其业务依赖 FK 均**不在相应主码内** | 当前**物理图不画双矩形弱实体**；17 条 FK 均不参与子表 PK，使用**非标识性虚线联系**。概念层可以讨论“弱实体”的替代设计，但不能冒称 v0.1 已采用依赖主码 |
| **存在依赖 / 关联实体** | 一条 `OrderDetails` 必须有一张订单和一种商品；`Inventory`、`TokenBalances` 必须关联父行 | 这是**存在依赖**，并非严格弱实体的充分条件。图上 `OrderDetails` 标为“关联实体”，`Inventory`/ `TokenBalances` 提示“依赖”，不改 PK |
| **多值属性** | `Users.phone` 是一个可空标量；多种商品通过多条 `OrderDetails` 行保存；`Roles.permissions` 是 JSON 字段，但 `ISJSON` 只保证语法，不能证明其具体多值语义 | **没有能由当前设计可靠确认的经典多值属性**，因此不画双椭圆、不臆造独立多值表。若将来业务要求用户多个电话或复杂权限项，六周再明确是否分拆 |
| **复合属性** | `(model_provider,token_amount)`、`(order_id,product_id)` 是两个字段组成的候选键，而不是一个可进一步拆分的地址/姓名类属性 | 当前没有明确的复合属性分解；**复合候选码 ≠ 复合属性**。图中分别显示字段与 UK 标注 |
| **派生属性 / 存储计算结果** | `OrderDetails.subtotal = quantity × unit_price`、`total_tokens = quantity × tokens_per_unit`，第四周添加了公式 CHECK | 两字段是**计算得出但实际存储的列**。图中标注“计算存储”，**不是 SQL Server 计算列**，也不应该误画为没有实际存储的纯虚拟属性 |
| **冗余汇总 / 余额快照** | `Orders.total_amount/total_tokens` 与明细求和；`UsageSummary` 的用量统计；`Inventory.current_quota`、`TokenBalances.remaining_tokens` 是状态值 | 图中区分“汇总存储/周期汇总/额度快照/余额快照”。跨表等式靠 `verify.sql` 校验；不能把这些实际列描绘成运行时自动计算的属性 |
| **联系属性 / 多对多转实体** | 订单与商品的购买联系包含 `quantity`、`unit_price`、`subtotal`、`tokens_per_unit` 等 | `OrderDetails` 作为**关联实体**保存联系属性，图中只画 Orders—OrderDetails—Products 两条实际 FK；不要再增加一条没有真实 FK 的 Orders—Products 直连 |
| **三元/多元业务事实** | `TokenUsageLogs` 同时必填 `user_id`、`product_id`、`account_id`，每行是一次调用涉及会员、套餐、上游账号的**三方业务事实** | 图中标“**三方调用**”，保留通向该事件实体的**三条独立 FK**，而不是凭空增加第三方关系表或删除实体。provider 相同与账号有效期另行核验 |
| **同两实体间多角色联系** | `RestockTask.created_by`、`RestockTask.assigned_to` 分别指向 `Employees.employee_id` | 必须画**两条线**，以 `created_by`（非空，子→父 1..1）与 `assigned_to`（可空，子→父 0..1）区分；每名员工可创建/被指派 0..* 个任务 |
| **可选参与/非完整参与** | `UpstreamAccount` 可以没有 `Inventory`；一张 `Orders` 可在物理约束下没有 `OrderDetails` | 在图上严格按物理 DDL 显示 0..1 或 0..*，另在规则清单写明经营期望的 1..1/1..*；样例恰好存在对应行不改变结构保证 |
| **多态弱引用（非真实 FK）** | `InventoryLog.reference_type/reference_id`、`ExceptionLog.related_table/related_id` 用类型和 ID 表示关联，但 DDL 没有真实 FK | 仅显示普通属性、在文档标注为**逻辑弱引用**；不绘制未经数据库保证的联系线。这里的“弱引用”也**不是“弱实体”** |
| **父实体 / 分类继承** | provider 是字符枚举；`Roles` 表和四个 SQL Server 数据库角色不同 | 无足够依据新增 `Provider` 实体、供应商子类型或继承层次；不凭名称假设 ISA 关系 |

## B. 为什么使用非标识性外键线

本周选择的是**实际 v0.1 物理 ER**：各实体都有单独的主码；17 条实际外码均不包含在子表的 PK 中。虽然 `OrderDetails(order_id, product_id)`、`Inventory(account_id)`、`TokenBalances(user_id, model_provider)` 等额外 UNIQUE 键反映业务身份或一对一限制，它们不是表定义中的主码，不能因此将 Mermaid 实线标识性联系当作已有设计。

- 可编辑 Mermaid：`..` 表示**非标识性联系**（导出为虚线）；`--` 可表示标识性联系，此版本**不使用**。
- 导出 SVG/PNG：每条关系两端使用 `1..1`、`0..1`、`0..*` 或 `1..*` 文本，不使用鸟爪符号文字。
- PK、FK、UK 在实体框中仍以文本标注；多对多通过 `OrderDetails` 实体消解，**17 条线与 17 条数据库 FK 一一对应**。

如果第六周改用外码参与主码的设计，应在变更 DDL 后重新判定标识性联系与弱实体，届时再添加特殊外形，不能先在第五周图上画成数据库已经保证。

## C. 演示时可直接回答的问题

1. **为什么 OrderDetails 没有双矩形？** 因为本版有独立 `detail_id PK`，是依赖订单和商品的**关联实体**，但不是当前物理主码意义下的严格弱实体。
2. **为什么没有“多值属性”的双椭圆？** 因为现有字段未能证明哪个属性是同一实体的一组并列重复值。多个套餐在关联表里，是多对多业务关系，不是 Users 或 Orders 的一个多值列。
3. **为什么 subtotal 上写“计算存储”？** 它实际存储在明细中，公式由 CHECK 约束；`Orders.total_amount` 是跨表汇总存储，需要回归核对，级别不同。
4. **为什么调用日志有三条线？** 一次调用必须同时指向一个用户、一款产品、一个上游账号；是一个三元业务事实的事件实现，但数据库里确实是三条独立 FK。
5. **为什么员工与补货任务有两条线？** 任务的创建人必须有，指派人可无，且可以指向两个不同员工。
6. **虚线是什么意思？** 它表示“此 FK 不参与子表的主码”，不是“关联不重要”，也不表示 FK 可为 NULL。是否可空要看 `0..1` / `1..1` 标注。

**结论**：本版适合标注关联实体、存储计算字段、存储汇总字段、三方业务事实、多个角色 FK 和可选参与性；**不能无依据添加弱实体双矩形、多值属性双椭圆、继承或额外外码关系**。
