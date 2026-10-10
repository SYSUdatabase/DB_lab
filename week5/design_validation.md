# 第五周 ER 设计说明与验证记录

- **范围**：API Token 中转站 v0.1，2026-10-10 的第五周 ER 模型与业务解释。
- **核对内容**：实体、属性、主码与候选码、联系基数、参与约束，以及它们与 SQL 结构的对应关系。
- **资料**：第五周任务书；`sql/01_create_tables.sql`、`sql/constraint.sql`、`sql/verify.sql`、`report/stage_report.md`。
- **只读验证环境**：`LAPTOP-3H5FCR3B`，SQL Server `localhost\SQLEXPRESS`，数据库 `TokenHubDB_v01_A`。运行 `result/week5/readonly_validation.sql`；**全部为 SELECT/系统目录只读查询**。查询输出：`result/week5/readonly_validation.log`。
- **修改范围**：仅本周报告、ER 图及只读证据。未修改 v0.1 结构、数据、历史证据，也未运行迁移。

## 1. ER 设计思想：为什么这样分实体

系统不卖“一个具体上游账号”，而卖 `Products` 中描述的 Token 套餐。一个会员 `Users` 可以产生多张 `Orders`，一个订单可包含多条 `OrderDetails`，一件套餐又可出现于多张订单的明细。于是原本的“订单—商品”多对多转成两条一对多：`Orders 1 → N OrderDetails N ← 1 Products`。独立 `detail_id` 是明细主码，`(order_id, product_id)` 是额外的复合候选码。**不同商品的多条明细**已支持，**同商品重复明细行**当前被 UNIQUE 禁止，这一点需经小组确定。

支付和调用不是同一实体：`Orders` 保存订单状态和快照总额，`TokenBalances` 保存会员×provider 的余额快照，`TokenUsageLogs` 保存一次调用消耗的商品和上游账号，`UpstreamAccount` + `Inventory` 记录现有额度，`InventoryLog` 记录变化历史。不能将 `Products` 的套餐数量当作 `Inventory.current_quota` 的直接来源。

其余独立实体用于员工管理（`Roles`/ `Employees`）、使用统计（`UsageSummary`）、运营补货（`RestockTask`）和异常处理（`ExceptionLog`）。数据库中没有单独的 Provider 实体，现有 provider 值是字符串枚举；不能凭语义补画一条实际 FK。

图示文件：
- 可编辑原始 ER：[`er_diagram.mmd`](er_diagram.mmd)。
- 可放大导出图：[`er_diagram.svg`](er_diagram.svg)、[`er_diagram.png`](er_diagram.png)；[`render_er.py`](render_er.py) 可按源文件重新生成导出图。
- 主码与所有主要属性：[`data_dictionary.md`](data_dictionary.md)。
- 17 条现有 FK 的两端 min/max 与业务规则：[`business_rules_mapping.md`](business_rules_mapping.md)。
- 弱实体、存在依赖、多值/复合属性、计算与汇总字段、三方事实和非标识性联系：[`special_er_features.md`](special_er_features.md)。

**新版图示说明**：导出的 SVG/PNG 在线的两端直接标注 `1..1`、`0..1`、`0..*`、`1..*`，采用文字图例说明主码、外码和最小/最大基数；使用不规则布局和避障折线减少交叉。导出 SVG/PNG 所有联系均画**实线**，实线仅表示实体间现有外码关联，是否标识性取决于 FK 是否参与子表 PK，是否可空取决于 DDL 和两端基数。可编辑 `.mmd` 用 Mermaid `..` 保留非标识性语义，直接使用 Mermaid 渲染可能呈虚线，与本项目的 Python 输出图风格不同。图上 `Employees → RestockTask` 的两条线分别表示必填创建人 `created_by`（任务端 1..1）和可空指派人 `assigned_to`（任务端 0..1），并不是画重。图中“计算存储”“汇总存储”“余额快照”等是实际保存列的语义标注，而不是数据库自动计算列。可编辑 `.mmd` 使用 Mermaid 关系语法。图以当前 SQL DDL **物理约束**为主体，业务要求不同处另在文档说明。

## 2. 场景一：一张订单购买多个商品

**ER 路径**：`Users.user_id → Orders.user_id`；`Orders.order_id → OrderDetails.order_id`；`OrderDetails.product_id → Products.product_id`。

业务过程：用户产生订单头 → 每个购买的商品形成一条订单明细 → 明细保存下单时单价、数量与 Token 快照 → 汇总订单金额和总 Token。

只读执行 SQL（已由本周记录脚本验证）：

```sql
SELECT o.order_id, COUNT(*) AS detail_lines,
       COUNT(DISTINCT d.product_id) AS distinct_products
FROM dbo.Orders o
JOIN dbo.OrderDetails d ON d.order_id = o.order_id
GROUP BY o.order_id
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC, o.order_id;

SELECT COUNT(*) AS orders_without_details
FROM dbo.Orders o
WHERE NOT EXISTS (
  SELECT 1 FROM dbo.OrderDetails d WHERE d.order_id = o.order_id
);
```

**查询结果**：100 张订单、184 条订单明细，**68 张订单至少两条明细**；样例订单 5、11、15、16、17 均有 3 条、3 种不同商品；订单头与明细总额/Token 不一致为 **0**。没有明细的订单为 **0**。证据 `result/week5/readonly_validation.log` W5-02。

**限制**：不应把样例中的“0 张无明细订单”描述成 FK 已禁止无明细订单。当前 `Orders → OrderDetails` 的物理 min/max 是 **0..***，业务希望 **1..***；亦不应将 `UQ_OrderDetails_order_product` 忽略。

## 3. 场景二：会员下单与“散客”

**ER 路径**：`Users ||--o{ Orders`，每张订单的 `user_id` 必填，且指向一条已有用户记录。

```sql
SELECT COUNT(DISTINCT user_id) AS members_with_orders FROM dbo.Orders;
SELECT COUNT(*) AS orders_with_nonexistent_members
FROM dbo.Orders o
WHERE NOT EXISTS(
  SELECT 1 FROM dbo.Users u WHERE u.user_id=o.user_id
);
```

**查询结果**：28 位不同用户至少下过订单，100 条订单中 `orders_with_nonexistent_members=0`（W5-03）。

**对于“散客购买”必须说明边界**：当前 `Orders.user_id NOT NULL`，未实现直接用 `NULL user_id` 记录无账户散客。若散客必须创建一个临时用户档案，则仍可能按 `Users` 模型落单，但项目目前**没有已验证的临时散客方案**。第五周只记录设计分歧，第六周在明确业务需求后决定如何调整。

## 4. 场景三：上游库存查询与流水

**ER 路径**：`UpstreamAccount ||--o| Inventory`；`UpstreamAccount ||--o{ InventoryLog`；`UpstreamAccount ||--o{ TokenUsageLogs`。

- `UpstreamAccount` 包含 provider、总配额 `total_quota`、已用配额 `used_quota`、安全阈值 `safety_threshold` 等；
- `Inventory.current_quota` 是当前剩余额度（不是商品库存“件数”）；
- `InventoryLog` 按账号记录额度增减及操作人（可为空）；
- `Products` 与 `Inventory` 没有直接 FK，只有现有 API 调用日志能记录具体消耗账号。

```sql
SELECT a.provider,
       COUNT(*) AS account_count,
       SUM(i.current_quota) AS total_remaining,
       SUM(CASE WHEN i.current_quota < a.safety_threshold THEN 1 ELSE 0 END)
         AS below_safety_threshold
FROM dbo.UpstreamAccount a
JOIN dbo.Inventory i ON i.account_id=a.account_id
GROUP BY a.provider ORDER BY a.provider;
```

**查询结果**：OpenAI 3 个上游账号、额度 3,800,000，低库存 0；Claude 3 个、额度 2,150,000，低库存 0；Gemini 2 个、额度 400,000，低库存 **2**。库存缺失账号为 0，`current_quota != total_quota - used_quota` 为 0，调用日志 provider 错配为 0（W5-04）。

**注意区分时间口径**：此查询针对当前库中的样例额度数据与阈值，并不代表实时服务可用性。原第四周 `v_InventoryStatus` 使用固定历史样例快照；不能把历史核对时间说成当前现有业务时钟，也不能将“低于阈值”视为“账号可用且可补货”。

## 5. 参与约束与外码核验

完整的 17 条 FK 请看 [业务规则映射](business_rules_mapping.md) F01—F17。现场 `sys.foreign_keys` 只读目录查询实际返回 **17** 条启用的 FK；第四周追加的金额公式、Token 公式和付款时点 CHECK 共 **3** 个。

| 例子 | 现在数据库已保证 | 业务上仍需要解释 |
|---|---|---|
| 用户—订单 | 每订单关联且只关联一个用户；用户可无订单 | 是否允许没有账户记录的散客 |
| 订单—明细 | 每明细一个有效订单；一订单允许 0..* 明细 | 业务要求至少 1 条明细 |
| 上游账号—库存 | 每库存一账号；一账号最多一库存行 | 是否必须有库存行 |
| 员工—库存流水 | 一流水可以无员工操作人 | 系统自动操作与人工操作的语义 |
| 员工—补货任务 | `created_by` 必填，`assigned_to` 可空 | 自动任务的创建主体 |
| 产品—调用—上游 | 日志分别关联有效商品和有效账号 ID | 双方 provider 相等、账号在使用时有效不由 FK 单独保证 |

## 6. 文件与检查结果

| 核对内容 | 文件与证据 | 状态 |
|---|---|---|
| ER 源与导出图 | er_diagram.mmd、er_diagram.svg/png、render_er.py | 14 实体、17 FK；文件已生成 |
| 属性、主码、候选码 | data_dictionary.md | 已核对 |
| 联系的 min/max 和参与约束 | business_rules_mapping.md | 已核对 |
| v0.1 问题与保留理由 | v01_issues.md | 已记录，部分业务定义待确认 |
| 多商品订单、会员与散客、上游库存 | 第 2—4 节及 readonly_validation.log | 查询已执行 |
| ER 模型与 DDL 人工复核 | `er_diagram.mmd`、`data_dictionary.md`、`business_rules_mapping.md`、`independent_review.md` | **阮依成已完成复核**；14 实体、17 FK、标识与基数已核对 |
| 业务规则的后续取舍 | `v01_issues.md` 的 I02、I03、I04、I07 | **待确定具体方案**，不影响本周模型复核完成 |
| 数据库结构调整 | 第五周仅登记问题 | 未实施 |

## 7. 查询复现与待确认事项

从仓库根目录执行下面的**只读查询**，无需复建数据库（确保已有 `TokenHubDB_v01_A`，不更改 SQL Server 凭据或服务器设置）：

```powershell
sqlcmd -S 'localhost\SQLEXPRESS' -d 'TokenHubDB_v01_A' -E -C -b -W -i '.\result\week5\readonly_validation.sql'
```

该日志记录了 2026-10-10 对上述数据库执行的只读查询。若本机没有该库，应确认目标库结构一致后再指定名称；不要为核对而擅自创建、清理或覆盖数据库。**人工复核**：阮依成已完成 ER 图与 DDL、联系基数及问题清单的核对。**尚待业务决策**：散客身份方案、同单同商品能否多行、账号与库存是否必须一对一、自动补货任务的创建主体；具体方案留在 [问题清单](v01_issues.md)，本周不实施迁移。
