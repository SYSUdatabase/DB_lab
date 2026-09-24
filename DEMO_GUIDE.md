# DB_lab 第三周复现与现场演示指南

> 适用对象：仓库所有小组成员、助教复现、课堂展示  
> 目标：任何成员克隆仓库后，都能从空数据库复现第三周成果，并按同一套流程完成演示。  
> 数据库：`TokenHubDB_Week3`  
> 默认 SQL Server 实例：`localhost\SQLEXPRESS`

## 1. 这份教程要完成什么

完成本教程后，应能够证明：

1. 可以从空数据库开始创建数据库和 14 张业务表。
2. 主键、唯一约束、外键、非空、默认值和 CHECK 约束真实生效。
3. 样例数据不是孤立随机数据，而是满足订单、库存、流水等业务关系。
4. Products、Inventory、Orders 可以完成 CRUD。
5. 删除实验数据库后，按脚本重放可以得到一致结果。

## 2. 仓库结构

在仓库根目录应看到：

```text
DB_lab/
├── README.md
├── requirements.txt
├── week2_deliverables_v2.md
├── week3_plan.md
├──week3/
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

## 3. 环境要求

必需环境：

- Windows 10/11。
- SQL Server 2025 Express。
- SSMS（SQL Server Management Studio）。
- `sqlcmd` 命令行工具。
- Python 3.11 或更高版本。

Python 运行时没有第三方依赖；`week3/tools/datagen.py` 只使用标准库。
`requirements.txt` 中的 `ruff` 仅用于开发期代码检查，不影响数据库复现。

首次准备时，可以在 PowerShell 中检查：

```powershell
python --version
sqlcmd -?
```

SQL Server 默认连接目标：

```text
localhost\SQLEXPRESS
```

如果你本机实例名不同，需要把后文所有 `localhost\SQLEXPRESS` 替换成自己的实例名。

## 4. 获取仓库后先做什么

克隆仓库后进入根目录：

```powershell
git clone <仓库地址>
cd DB_lab
```

如果已经有仓库：

```powershell
git pull
```

检查第三周文件：

```powershell
Get-ChildItem .\week3\sql
Get-ChildItem .\week3\tools
```

应至少看到四个 SQL 文件和 `datagen.py`。

## 5. 第一次从空库复现

进入 SQL 目录：

```powershell
cd .\week3\sql
```

按编号顺序执行：

```powershell
sqlcmd -S "localhost\SQLEXPRESS" -E -C -b -f 65001 -i ".\00_create_database.sql"
sqlcmd -S "localhost\SQLEXPRESS" -E -C -b -f 65001 -i ".\01_create_tables.sql"
sqlcmd -S "localhost\SQLEXPRESS" -E -C -b -f 65001 -i ".\02_insert_data.sql"
sqlcmd -S "localhost\SQLEXPRESS" -E -C -b -f 65001 -i ".\03_crud_demo.sql"
```

四个文件的职责：

- `00_create_database.sql`：创建 `TokenHubDB_Week3`。
- `01_create_tables.sql`：创建 14 张表及约束。
- `02_insert_data.sql`：插入可复现样例数据。
- `03_crud_demo.sql`：执行商品、库存、订单 CRUD 演示；演示数据最终回滚，不污染基础数据。

如果某一步返回错误，先处理错误，不要跳过继续执行。

## 6. 用 SSMS 检查数据库

打开 SSMS，连接：

```text
Server name: localhost\SQLEXPRESS
Authentication: Windows Authentication
```

刷新：

```text
Databases
└── TokenHubDB_Week3
    └── Tables
```

应看到 14 张用户表。

也可以执行：

```sql
USE TokenHubDB_Week3;

SELECT COUNT(*) AS table_count
FROM sys.tables
WHERE is_ms_shipped = 0;
```

预期：

```text
table_count = 14
```

## 7. 重新生成样例数据

从仓库根目录执行：

```powershell
python -B .\week3\tools\datagen.py
```

关键输出应包括：

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

其中最重要的是：

```text
self_check=PASS
```

固定随机种子保证同一版本生成器得到相同数据。

生成器会检查：

- Orders 汇总金额与 OrderDetails 一致。
- Orders 汇总 Token 与 OrderDetails 一致。
- Token 余额非负。
- Inventory 与 UpstreamAccount 的额度关系一致。
- Inventory 与 InventoryLog 流水净额一致。
- 关键外键引用存在。
- 上游账号中的 API Key 全部是教学占位符。

## 8. 快速核对基础数据

在 SSMS 执行：

```sql
USE TokenHubDB_Week3;

SELECT COUNT(*) AS user_count FROM dbo.Users;
SELECT COUNT(*) AS order_count FROM dbo.Orders;
SELECT COUNT(*) AS usage_count FROM dbo.TokenUsageLogs;
```

预期：

```text
Users = 40
Orders = 100
TokenUsageLogs = 3000
```

继续检查订单签名：

```sql
SELECT
    COUNT(*) AS orders_count,
    SUM(total_amount) AS orders_amount,
    SUM(total_tokens) AS orders_tokens
FROM dbo.Orders;
```

预期：

```text
orders_count = 100
orders_amount = 4931.00
orders_tokens = 108950000
```

Token 使用签名：

```sql
SELECT
    COUNT(*) AS usage_count,
    SUM(CAST(tokens_used AS BIGINT)) AS usage_tokens,
    SUM(CAST(upstream_tokens_consumed AS BIGINT)) AS usage_upstream
FROM dbo.TokenUsageLogs;
```

预期：

```text
usage_count = 3000
usage_tokens = 6040100
usage_upstream = 7248120
```

## 9. 业务关系展示

### 9.1 用户与订单

```sql
SELECT TOP 10
    o.order_id,
    u.username,
    o.status,
    o.total_amount,
    o.total_tokens
FROM dbo.Orders AS o
JOIN dbo.Users AS u ON u.user_id = o.user_id
ORDER BY o.order_id;
```

展示重点：订单中的 `user_id` 可以连接到真实用户。

### 9.2 订单、明细与商品

```sql
SELECT TOP 10
    o.order_id,
    p.name AS product_name,
    d.quantity,
    d.unit_price,
    d.subtotal,
    d.total_tokens
FROM dbo.OrderDetails AS d
JOIN dbo.Orders AS o ON o.order_id = d.order_id
JOIN dbo.Products AS p ON p.product_id = d.product_id
ORDER BY o.order_id;
```

展示重点：样例数据存在完整业务联系，不是独立随机行。

## 10. CRUD 演示

推荐直接打开：

```text
week3/sql/03_crud_demo.sql
```

脚本包含三组演示：

### A. Products

依次展示：

```text
SELECT → INSERT → SELECT → UPDATE → SELECT → DELETE → SELECT
```

说明：

- 插入临时套餐。
- 修改价格和状态。
- 删除临时套餐。
- 最终事务回滚，所以正式样例数据保持不变。

### B. Inventory

演示逻辑：

1. 新建一个临时 UpstreamAccount。
2. 为该账号建立 Inventory。
3. 将 `current_quota` 从 100000 修改到 99000。
4. 删除临时库存和账号。
5. 回滚事务。

这里要解释：库存表示上游 API 账号可用额度，因此 Inventory 关联 UpstreamAccount，而不是 Products。

### C. Orders

演示逻辑：

1. 创建临时订单。
2. 创建对应 OrderDetails。
3. 将订单状态从 pending 更新为 paid。
4. 删除时先删 OrderDetails，再删 Orders。
5. 回滚事务。

这里要解释外键决定了父子表的创建和删除顺序。

## 11. 约束演示

### 11.1 负价格必须失败

```sql
INSERT INTO dbo.Products
(
    name, price, model_provider,
    token_amount, required_upstream_tokens, status
)
VALUES
(
    N'非法价格测试', -1.00, 'Other',
    1, 1, 'active'
);
```

预期：SQL Server 报 CHECK 约束错误。

解释：`Products.price` 必须大于 0。

### 11.2 不存在的用户不能下订单

```sql
INSERT INTO dbo.Orders
(
    user_id, total_amount, total_tokens, status
)
VALUES
(
    999999, 1.00, 1, 'pending'
);
```

预期：SQL Server 报外键错误。

解释：`Orders.user_id` 必须引用真实存在的 `Users.user_id`。

## 12. 一致性演示

订单一致性：

```sql
WITH d AS (
    SELECT order_id,
           SUM(subtotal) AS detail_amount,
           SUM(total_tokens) AS detail_tokens
    FROM dbo.OrderDetails
    GROUP BY order_id
)
SELECT COUNT(*) AS mismatch_count
FROM dbo.Orders AS o
JOIN d ON d.order_id = o.order_id
WHERE o.total_amount <> d.detail_amount
   OR o.total_tokens <> d.detail_tokens;
```

预期：

```text
mismatch_count = 0
```

库存一致性：

```sql
WITH l AS (
    SELECT account_id,
           SUM(change_amount) AS log_balance
    FROM dbo.InventoryLog
    GROUP BY account_id
)
SELECT COUNT(*) AS mismatch_count
FROM dbo.UpstreamAccount AS a
JOIN dbo.Inventory AS i ON i.account_id = a.account_id
JOIN l ON l.account_id = a.account_id
WHERE i.current_quota <> a.total_quota - a.used_quota
   OR i.current_quota <> l.log_balance;
```

预期：

```text
mismatch_count = 0
```

库存三层语义：

- `total_quota`：累计采购额度。
- `used_quota`：累计已使用额度。
- `Inventory.current_quota`：当前可用额度。
- `InventoryLog`：每次增加/减少的历史流水。

## 13. 重复做“从空库复现”

如果数据库已经存在，`00_create_database.sql` 会主动拒绝覆盖。

只有在确认可以删除本项目实验库时，才执行：

```sql
USE master;

IF DB_ID(N'TokenHubDB_Week3') IS NOT NULL
BEGIN
    ALTER DATABASE TokenHubDB_Week3
        SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE TokenHubDB_Week3;
END;
```

注意：只允许删除 `TokenHubDB_Week3`，不要删除其他数据库。

删除后重新执行第 5 节的四条 `sqlcmd` 命令。

重建完成后重新执行第 8 节检查；关键统计应与原结果一致。

## 14. 常见问题与处理

### sqlcmd 找不到

先检查：

```powershell
Get-Command sqlcmd
```

如果不存在，需要安装 SQL Server 命令行工具；也可以暂时在 SSMS 中依次打开并执行 00～03。

### 无法连接 localhost\SQLEXPRESS

检查 SQL Server Express 服务是否启动，并确认实际实例名称。
如果本机实例不是 `SQLEXPRESS`，把教程中的服务器名替换成实际实例。

### 00_create_database.sql 提示数据库已存在

这是保护机制，不是脚本故障。
如果只是展示已有数据库，不需要重建。
如果确实要从空库复现，按第 13 节只删除 `TokenHubDB_Week3` 后再执行。

### datagen.py 运行后数据与预期不同

先确认仓库版本一致：

```powershell
git status
git log -1 --oneline
```

然后重新运行生成器。
固定随机种子版本下，输出行数和关键签名应一致。

### 02_insert_data.sql 很大，要不要现场打开

不建议。
它是生成器产物，接近一万行。演示时展示 `datagen.py` 的设计和 `self_check=PASS` 更有价值。

## 15. 演示时必须知道的设计理由

### 为什么金额用 DECIMAL 而不是 FLOAT？

金额要求精确，FLOAT 是近似浮点类型，因此使用 `DECIMAL(10,2)`。

### 为什么时间用 DATETIME2(0)？

它是现代 SQL Server 推荐使用的日期时间类型之一；本实验只需要精确到秒。

### 为什么中文文本使用 NVARCHAR？

避免依赖数据库默认代码页，保证中文业务文本稳定保存。

### 为什么 Inventory 关联 UpstreamAccount？

本项目库存表示“上游账号剩余 Token 额度”，不是“商品还剩多少件”。

### 为什么 Orders 和 OrderDetails 都保存 total_tokens？

OrderDetails 保存分项值，Orders 保存汇总值，属于为了查询便利保留的受控冗余；生成器负责检查两者一致。

## 16. 安全与演示注意事项

- 不要展示、读取或提交真实 API Key。
- 仓库中的 API Key 仅为 `DEMO_NOT_A_REAL_API_KEY_*` 占位符。
- 不要在课堂上随意删除其他数据库。
- 重建时只操作 `TokenHubDB_Week3`。
- 不要删除 UPDATE / DELETE 中的 WHERE。
- 不要现场手工修改 `02_insert_data.sql`。
- CRUD 演示优先使用项目现有事务脚本，避免污染基础数据。

## 17. 演示前最终检查清单

```text
□ 已拉取最新仓库
□ SQL Server Express 正常运行
□ SSMS 可连接实际 SQL Server 实例
□ sqlcmd 可用
□ Python >= 3.11
□ 00～05 六个 SQL 文件存在
□ datagen.py 存在
□ TokenHubDB_Week3 已创建或确认可重建
□ 14 张业务表存在
□ datagen.py 输出 self_check=PASS
□ Users = 40
□ Orders = 100
□ TokenUsageLogs = 3000
□ 订单一致性 mismatch_count = 0
□ 库存一致性 mismatch_count = 0
□ 约束演示两条均报错
□ 知道 Inventory 为什么关联 UpstreamAccount
□ 知道 DECIMAL / NVARCHAR / DATETIME2 的选择理由
□ 不会展示任何真实密钥
```
