# 第六周：函数依赖、候选码、1NF / 2NF / 3NF 及更新异常

对象：`sql/01_create_tables.sql` 定义的 14 张表；追加跨列约束来自 `sql/constraint.sql`。实际数据检查：`week6/fd_checks.sql`、`result/week6/baseline/fd_checks.log`；数据库 `TokenHubDB_v10_W6_20261014`（v0.1 副本）。

**判断原则**：所有候选码都参与 2NF / 3NF 检查，不只看自增主码。函数依赖由 **业务规则或 DDL** 推出，不能用样例没有冲突来证明。下文 `K → 其余属性` 表示候选码按键约束决定同一行剩余属性。唯一键均参见 `week5/data_dictionary.md`。当前数据库中的非空业务属性均为 SQL 标量；`Roles.permissions` 使用 JSON 存储，是否存在应拆开的重复授权项需要另外定义应用权限语义。

## 1. 全部 14 张表逐项判断

| 表 | 候选码（PK 为首项） | 关键非平凡 FD / 前提 | 1NF | 2NF | 3NF | 插入 / 修改 / 删除异常的现有判断 |
|---|---|---|---|---|---|---|
| `Roles` | `role_id`；`role_name` | `role_id→role_name,permissions,description`；`role_name→role_id,...`（UNIQUE + 非空） | 是* | 是 | 是* | 插入相同角色名由 UK 拒绝；修改权限只改一行；删除角色如有 Employees 引用由 FK 拒绝。JSON 权限细粒度更新需要业务确认 |
| `Users` | `user_id`；`username`；`email` | 各候选码决定其余列（DDL）；`phone→user_id` **不成立** | 是 | 是 | 是 | 重复 username/email 插入被拒；修改资料按 user_id 定位；删除有订单/余额用户受外码保护 |
| `Products` | `product_id`；`name`；`(model_provider,token_amount)` | 三种候选码均决定套餐现价、状态、折算量等（DDL）；**product_id 不决定历史 OrderDetails.unit_price**（不同表/时间） | 是 | 是 | 是 | 重复同 provider/档位拒绝；修改当前价不能反算历史成交价；已有订单商品受 FK 保护，不因删商品消失 |
| `UpstreamAccount` | `account_id`；`(provider,account_name)` | 两种码决定配额、阈值、状态（DDL）；跨表额度方程不是该表内部的非码→非码 FD | 是 | 是 | 是 | 重复同 provider 账号名拒绝；更新总配额/已用配额后必须同步库存快照；已有日志/库存的账号不能无约束删除 |
| `Inventory` | `inventory_id`；`account_id` | 两种码决定 current_quota、更新时间（UK/FK）；账号侧是否必须有库存**未由外码保证** | 是 | 是 | 是 | 不能一账号插入两库存；账号额度改动可能令两表不同步；删除库存仍可能留下无库存账号，是参与规则缺口，不是本表 3NF 违例 |
| `Employees` | `employee_id`；`account` | 两种码决定姓名、role_id、雇佣日期（DDL）；`role_id` 不决定员工姓名 | 是 | 是 | 是 | 账号重复拒绝；角色改变改一行且 FK 有效；被补货/日志引用的员工受 FK 保护 |
| `Orders` | `order_id` | `order_id→user_id,total_amount,total_tokens,status,paid_at,...`；总额为明细的跨表求和，不是本表非码决定项 | 是 | 是 | 是† | 订单头可单独插入而没有明细（业务插入异常）；增删明细须同步总额（跨表修改异常）；删除订单受明细 FK 阻止 |
| `OrderDetails` | `detail_id`；`(order_id,product_id)` | 两种码决定所有其他列；**(quantity,unit_price)→subtotal** 及 **(quantity,tokens_per_unit)→total_tokens**（同表公式 CHECK） | 是 | 是‡ | **否（按含存储计算列的关系模型）** | 公式不符 INSERT/UPDATE 已被 CHECK 拒绝，但需同时输入两项手工冗余值；删除明细需同步订单汇总。快照单价/Token 档位保留，不根据商品现价重算 |
| `InventoryLog` | `log_id` | `log_id→account_id,change_type,change_amount,...`；多态 reference_id **不是受 FK 保护的码** | 是 | 是 | 是 | 插入弱引用可以不指向真实目标；更改指向目标无外码校验；删除目标可能留下逻辑悬空流水 |
| `TokenBalances` | `balance_id`；`(user_id,model_provider)` | 两码决定 remaining_tokens,updated_at；余额是跨交易的快照，不表示 provider 值可决定余额 | 是 | 是 | 是† | 同人同 provider 重复余额拒绝；支付/调用未同步会造成跨表更新异常；删除用户受 FK 保护，但快照历史需单独保留 |
| `TokenUsageLogs` | `log_id` | `log_id→user_id,product_id,account_id,tokens_used,...`；`product_id` 与 `account_id` 的 provider 相等不是单表 FD | 是 | 是 | 是 | 多个事件可用同商品，不应误设 UNIQUE；跨表 provider 错配须校验；删除关联商品/账号受 FK 防止丢失引用 |
| `UsageSummary` | `summary_id`；`(user_id,product_id,period_type,period_start)` | 两码决定指标和 period_end；**若定义固定周期**，则 `(period_type,period_start)→period_end`，前件是复合候选码的真子集 | 是 | **有条件否** | **有条件否** | 同一周期起点在多个汇总行中可存不同 period_end，导致插入/修改不一致；删除最后一条用户汇总可能丢失周期定义。条件取决于业务是否规定全局统一的周期边界 |
| `RestockTask` | `task_id` | `task_id→account_id,created_by,assigned_to,status,...`；`created_by` 与 `assigned_to` 是不同角色，彼此无 FD | 是 | 是 | 是 | 自动创建时 created_by 强制员工；更换受派人需合法 FK；删除创建员工/被指派人按 FK 保护 |
| `ExceptionLog` | `exception_id` | `exception_id→exception_type,related_table,related_id,handled_by,...`；related_table + related_id 不是安全的候选码/FK | 是 | 是 | 是 | 能插入不存在的弱引用；修改关联对象可能悬空；被指对象删除不被弱引用拦截 |

`*`：`Roles.permissions` 是一个可空 JSON 字段。SQL 存储列本身属于单列标量，但其内部是否含应独立规范化的多值权限集合，`ISJSON` 不能证明；若需要逐权限关系运算，另行考虑 `RolePermission(role_id,permission_code)`。

`†`：**关系范式与跨表受控冗余是两个问题**。Orders 或 TokenBalances 现有依赖来自订单/事件流水，但单表中没有充分证据出现非码→非码的 3NF 违例；仍须确保事务与回归对账。

`‡`：OrderDetails 的 `order_id`、`product_id` 单独并不能从已确认业务规则推出下单数量、成交价格，故**不能**因商品有当前价格而认定 `unit_price` 部分依赖 `product_id`。公式依赖属于非码→非码（3NF 问题），不是候选码真子集→非主属性（2NF 问题）。

## 2. 典型依赖和实际异常样例

### A. OrderDetails：需要受控反规范化

- 旧关系 `D(detail_id,order_id,product_id,quantity,unit_price,subtotal,tokens_per_unit,total_tokens)`。
- FD：`(quantity,unit_price)→subtotal`，`(quantity,tokens_per_unit)→total_tokens`，且两组决定因素都不包含候选码。
- 插入例：`quantity=2, unit_price=9.50, subtotal=18.00` 应被 CHECK 拒绝；正确 subtotal 是 19.00。现有 CHECK 能识别错误**但仍要求调用方重复传入计算结果**。
- 更新例：同一行 quantity 从 2 改 3，不更新 subtotal 则 CHECK 失败，须同时改为 28.50；删除时 OrderDetails 的减少需对应更新 Orders.total_amount。
- **保留历史快照理由**：`unit_price` 和 `tokens_per_unit` 必须保留“下单时”的取值，不能从后来修改的 Products.price 推导；属于必要业务历史属性。
- 可选处理：迁移到 SQL Server **PERSISTED computed** 列保持列名与查询兼容，但原 INSERT 显式提供 `subtotal,total_tokens` 将失败，必须同时改写生产写入路径/生成器；因此在 P2 决策前**不执行**。若保留原列，必须说明 CHECK 和事务保持受控冗余，属于有意保留的理论非 3NF。

### B. UsageSummary：条件性的部分依赖

- 若所有用户共享固定周期规则（daily：同日，weekly：起点后第 6 日，monthly：所在月末），`(period_type,period_start)→period_end`。
- `(period_type,period_start)` 是四元候选码 `(user_id,product_id,period_type,period_start)` 的真子集；`period_end` 是非主属性 ⇒ 违反 2NF，并可能导致多用户之间的周期结束日期不一致。
- 当下数据库 CHECK 只保证 `period_end >= period_start`；本周只读检查没有发现相同周期起点多结束日，但**样例无反例不证明 FD 已被数据库强制**。
- 若小组确认全局固定周期，可拆成 `UsagePeriod(period_type,period_start,period_end)` 和 `UsageSummary(summary_id,user_id,product_id,period_type,period_start,metrics...)`；通过 `(period_type,period_start)` 连接还原。拆分方案及需要改的 SQL/应用入口另见 `redesign_decisions.md`。
- 如果允许特定用户或商品自定义周期终点，前述 FD 不成立，不能仅因为示例数据相同就拆表。

### C. 假设性独立关系：用来解释异常，不把新业务实体硬加进仓库

`ProductCategoryDraft(product_id,product_name,category_id,category_name)`，业务约定 `product_id→category_id`、`category_id→category_name`，则有 `product_id→category_id→category_name`，存在传递依赖。三个异常：

1. **插入**：尚无商品的类别无法在该关系中单独保存。
2. **修改**：同一个类别名称散落多个商品行，若只改一处则矛盾。
3. **删除**：删掉某类别的最后一个商品会丢失类别名称。

分解 `Category(category_id,category_name)` 与 `ProductCategory(product_id,product_name,category_id)`：共同属性 `category_id` 是 Category 的键，故在上述 FD 下分解无损；`product_id→category_id`、`category_id→category_name` 各自可在某张新表检查，依赖保持。**v0.1 并无 Category 表/属性**，此例只用于说明方法，不构成本周待执行迁移。

## 3. 数据检查与解释

来自 `result/week6/baseline/fd_checks.log` 的只读结果：14 张表、17 条 FK；明细金额公式异常 0、Token 公式异常 0、同订单同商品重复行 0；订单汇总/库存对账异常均为 0。期间汇总中，同一 `(period_type,period_start)` 出现多种 `period_end` 的样例计数为 0；daily/weekly/monthly 的天数差分别为 0 / 6 / 29～30，属于样例特征，不能代替业务规定。

**初步结论**：除 OrderDetails 存储公式字段的确定性 3NF 问题外，UsageSummary 的范式问题受是否采用统一周期规则影响。其余 12 张表未发现由当前已确认业务 FD 引起的明确 1NF/2NF/3NF 问题；这不等于没有跨表一致性风险。迁移范围需先完成 P2 决策。

## 4. 源代码对固定周期 FD 的补充证据

补查 `tools/datagen.py` 生成 `UsageSummary` 的逻辑：daily 的起点/终点均为调用日期；weekly 使用 `used_date.weekday()` 将起点对齐周一，终点为六日后；monthly 将起点对齐该月 1 日，终点为该月最后一天。`sql/verify.sql` 的 VFY10 使用同样的周一/自然月规则生成参照并做双向 EXCEPT 比较。因而对**现有项目明确采用的统计定义**，`(period_type,period_start)→period_end` 是有代码与验收规则支持的业务 FD，而不再只是样例观察。数据库 `CK_UsageSummary_dates` 仍仅保证 end≥start，不保证该 FD；模式调整需要批准。

隔离副本只读计数：`UsageSummary` **3394 行**，其中不同的 `(period_type,period_start)` 共 **99 个**（daily 83、weekly 13、monthly 3），同键不同结束日 **0**。按上述 FD 提取周期定义表可将重复的日期规则统一管理，但必须同步旧的 `query.sql`、`verify.sql`、生成器与已有插入接口。
