# 第三周任务交付物：DDL 与数据修改

> 项目：API Token 中转站数据库
> 数据库：`TokenHubDB_Week3`
> 环境：SQL Server 2025 Express，实例 `localhost\SQLEXPRESS`
> 执行日期：2026-09-23
> 状态：已完成并通过空库复现验证

## 1. 本周目标完成情况

本周已将第二周的 14 张关系表从纸面设计落地为 SQL Server 可执行数据库，并完成：

- 从空数据库创建数据库与 14 张数据表；
- 主键、候选码、外键、非空、默认值、CHECK 约束；
- 固定随机种子的合成样例数据；
- 商品、库存、订单三类对象的 CRUD 演示；
- 订单汇总、库存流水等业务一致性校验；
- 非法价格和非法外键的约束冒烟测试；
- 删除本周实验库后，按脚本顺序重新执行并验证结果一致。

## 2. 文件结构

```text
week3/
├── sql/
│   ├── 00_create_database.sql
│   ├── 01_create_tables.sql
│   ├── 02_insert_data.sql
│   ├── 03_crud_demo.sql
│   ├── 04_constraint_demo.sql
│   └── 05_consistency_check.sql
├── tools/
│   └── datagen.py
└── week3_deliverables.md
```

其中 `02_insert_data.sql` 由 `tools/datagen.py` 生成，固定随机种子为 `20260923`。

## 3. 实现级调整

根据 `week3_plan.md` 中已经确认的实现决策，本周落地时进行了以下调整：

1. 第二周的 `TEXT` 字段改为 `NVARCHAR(MAX)`。
2. 可能包含中文的名称、说明、原因等字段使用 `NVARCHAR`。
3. 密码哈希样例严格保持 60 字符 bcrypt 形占位符。
4. 所有主键仍使用 `IDENTITY(1,1)`，样例数据通过 `IDENTITY_INSERT` 显式插入固定 ID。
5. 时间戳统一采用 `DATETIME2(0)`。
6. 状态枚举、数值范围、JSON 等域规则通过 CHECK 约束落地。
7. 所有 API Key 数据均为 `DEMO_NOT_A_REAL_API_KEY_*` 形式的教学占位符，不包含真实密钥。
8. 数据库采用 `Chinese_PRC_90_CI_AI_SC_UTF8` 排序规则；中文业务文本仍主要使用 NVARCHAR，避免依赖 VARCHAR 的编码行为。
9. 数据库层 `CREATE ROLE + GRANT` 暂未加入，本项按计划留到第四周权限任务。

## 4. 合成数据说明

生成器仅使用 Python 标准库，并使用固定随机种子保证可复现。

数据时间范围约为 2026-07-01 至 2026-09-22。商品定价方向参考 2026-09-23 检查的 OpenAI、Anthropic、Google 官方 API 定价信息，但本项目的套餐价格经过简化，仅用于数据库教学，不代表真实商业报价。

生成器保证以下业务联系：

- `Orders.total_amount = SUM(OrderDetails.subtotal)`；
- `Orders.total_tokens = SUM(OrderDetails.total_tokens)`；
- paid 订单形成用户 Token 余额；
- Token 使用记录扣减用户余额；
- 每条 Token 使用记录对应上游账号消耗；
- 上游账号消耗同步形成库存负流水；
- 完成的补货任务形成库存正流水；
- `Inventory.current_quota = UpstreamAccount.total_quota - used_quota`；
- `Inventory.current_quota = SUM(InventoryLog.change_amount)`；
- UsageSummary 从 TokenUsageLogs 聚合生成，而不是独立随机生成。

## 5. 最终数据量

| 表 | 行数 |
|---|---:|
| Roles | 3 |
| Users | 40 |
| Products | 10 |
| UpstreamAccount | 8 |
| Inventory | 8 |
| Employees | 6 |
| Orders | 100 |
| OrderDetails | 184 |
| InventoryLog | 3012 |
| TokenBalances | 61 |
| TokenUsageLogs | 3000 |
| UsageSummary | 3394 |
| RestockTask | 8 |
| ExceptionLog | 15 |

SQL Server 用户表数量检查结果：14 张。

## 6. CRUD 演示

`03_crud_demo.sql` 覆盖三个核心业务对象，并在写操作前后使用 SELECT 展示结果。

### 6.1 商品 Products

- CREATE：插入临时教学套餐；
- READ：查询插入后的记录；
- UPDATE：修改价格和状态；
- DELETE：删除临时套餐；
- 所有操作放在事务中，演示结束后 ROLLBACK，基础数据不被污染。

### 6.2 库存 Inventory

- CREATE：插入临时上游账号和对应库存记录；
- READ：查询临时库存；
- UPDATE：扣减 1000 Token 库存；
- DELETE：删除临时库存和临时上游账号；
- 最终 ROLLBACK。

### 6.3 订单 Orders

- CREATE：插入临时订单和订单明细；
- READ：连接查询订单与明细；
- UPDATE：将订单由 pending 改为 paid；
- DELETE：先删明细，再删订单；
- 最终 ROLLBACK。

## 6.4 约束演示

`04_constraint_demo.sql` 演示非法数据被拒绝：

- 负价格 → 被 `CK_Products_price` CHECK 约束拒绝；
- 不存在的用户下单 → 被 `FK_Orders_Users` 外键约束拒绝。

执行结果：两条 INSERT 均报错，数据库拒绝非法数据。

## 6.5 一致性校验

`05_consistency_check.sql` 验证业务数据闭环：

- `order_mismatch = 0`：订单汇总金额、Token 数与明细汇总完全一致；
- `inventory_mismatch = 0`：库存额度、上游账号额度、流水净额完全一致。

## 7. 验证结果

### 7.1 生成器自检

```text
seed=20260923
Users=40
Products=10
UpstreamAccount=8
Inventory=8
Employees=6
Orders=100
OrderDetails=184
InventoryLog=3012
TokenBalances=61
TokenUsageLogs=3000
UsageSummary=3394
RestockTask=8
ExceptionLog=15
self_check=PASS
```

### 7.2 数据库一致性

| 检查项 | 结果 |
|---|---:|
| 用户表数量 | 14 |
| 订单汇总不一致数 | 0 |
| 库存/流水不一致数 | 0 |
| 负价格 CHECK 约束 | PASS |
| Orders.user_id 外键约束 | PASS |

### 7.3 空库复现前后签名

第一次装载：

- Orders：100 行，总金额 4931.00，总 Token 108950000；
- TokenUsageLogs：3000 行，用户使用 Token 6040100，上游消耗 7248120；
- InventoryLog：3012 行，净变动 6350000；
- UsageSummary：3394 行，汇总 Token 18120300。

删除本次新建的 `TokenHubDB_Week3` 后，重新执行 `00 → 01 → 02 → 03`，上述数字完全一致，因此复现验证通过。

## 8. 从空数据库复现

在 PowerShell 中进入：

```powershell
cd D:\Desktop\DB\DB_lab\week3\sql
```

确认 `TokenHubDB_Week3` 不存在后，依次执行：

```powershell
sqlcmd -S "localhost\SQLEXPRESS" -E -C -b -f 65001 -i ".\00_create_database.sql"
sqlcmd -S "localhost\SQLEXPRESS" -E -C -b -f 65001 -i ".\01_create_tables.sql"
sqlcmd -S "localhost\SQLEXPRESS" -E -C -b -f 65001 -i ".\02_insert_data.sql"
sqlcmd -S "localhost\SQLEXPRESS" -E -C -b -f 65001 -i ".\03_crud_demo.sql"
sqlcmd -S "localhost\SQLEXPRESS" -E -C -b -f 65001 -i ".\04_constraint_demo.sql"
sqlcmd -S "localhost\SQLEXPRESS" -E -C -b -f 65001 -i ".\05_consistency_check.sql"
```

如果需要重新生成样例数据：

```powershell
cd D:\Desktop\DB\DB_lab\week3
python .\tools\datagen.py
```

由于随机种子固定，每次会生成相同的业务数据和固定 ID。

## 9. 工具检查

- Python：3.12.6；
- `python -m py_compile tools/datagen.py`：通过；
- `datagen.py` 自检：PASS；
- `ruff`：当前机器未安装，因此未执行 ruff 格式化；未为本次实验额外安装软件。

## 10. 第四周衔接

当前数据已经能够支持下一周的：

- 多表连接查询；
- 商品、订单、库存等统计视图；
- 非法数据约束演示；
- SQL Server 数据库角色和 GRANT 权限演示。

本周没有提前创建数据库层角色或视图，以保持第三周与第四周任务边界清晰。
