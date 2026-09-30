/*
第三周数据库实验：CRUD 演示脚本（注释版）。
目标：对 Products、Inventory、Orders 演示增查改删，并通过事务回滚避免污染基础样例数据。
*/

-- Week 3 / 03_crud_demo.sql
-- Each section shows SELECT before/after. Changes are rolled back so the base dataset remains reproducible.

USE [TokenHubDB_Week3];  -- 作用：切换数据库上下文，后续语句都在这个数据库中执行
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO
SET NOCOUNT ON;  -- 作用：关闭受影响行数提示，减少批量脚本输出噪声
SET XACT_ABORT ON;  -- 作用：让事务中的运行时错误自动终止事务，避免半成功状态
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

PRINT N'=== A. Products CRUD ===';  -- 作用：输出当前演示章节标题，便于区分不同 CRUD 段
BEGIN TRANSACTION;  -- 作用：开启事务，把后续一组写操作作为整体处理
SELECT product_id, name, price, status  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
FROM dbo.Products  -- 作用：指定当前 SELECT 查询的数据来源
WHERE name = N'CRUD演示临时套餐';  -- 作用：限定本次查询或修改只作用于满足条件的目标记录


-- =========================
-- Products 数据写入
-- =========================
-- 这一批语句用于填充 Products；固定 ID 保证后续外键引用稳定。
INSERT INTO dbo.Products  -- 作用：向 Products 表插入样例或演示数据
    (name, description, price, model_provider, token_amount, required_upstream_tokens, status)
VALUES  -- 作用：开始给出 INSERT 对应的字段值
    (N'CRUD演示临时套餐', N'仅用于第三周 CRUD 演示', 9.90, 'Other', 123456, 150000, 'active');  -- 作用：写入当前一行样例数据，字段顺序与本批 INSERT 列表一致

SELECT product_id, name, price, status  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
FROM dbo.Products  -- 作用：指定当前 SELECT 查询的数据来源
WHERE name = N'CRUD演示临时套餐';  -- 作用：限定本次查询或修改只作用于满足条件的目标记录

UPDATE dbo.Products  -- 作用：修改 Products 表中满足 WHERE 条件的记录
SET price = 12.90, status = 'inactive'
WHERE name = N'CRUD演示临时套餐';  -- 作用：限定本次查询或修改只作用于满足条件的目标记录

SELECT product_id, name, price, status  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
FROM dbo.Products  -- 作用：指定当前 SELECT 查询的数据来源
WHERE name = N'CRUD演示临时套餐';  -- 作用：限定本次查询或修改只作用于满足条件的目标记录

DELETE FROM dbo.Products  -- 作用：删除 Products 表中满足 WHERE 条件的演示记录
WHERE name = N'CRUD演示临时套餐';  -- 作用：限定本次查询或修改只作用于满足条件的目标记录

SELECT product_id, name, price, status  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
FROM dbo.Products  -- 作用：指定当前 SELECT 查询的数据来源
WHERE name = N'CRUD演示临时套餐';  -- 作用：限定本次查询或修改只作用于满足条件的目标记录
ROLLBACK TRANSACTION;  -- 作用：回滚本组 CRUD 演示，恢复基础样例数据
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

PRINT N'=== B. Inventory CRUD ===';  -- 作用：输出当前演示章节标题，便于区分不同 CRUD 段
BEGIN TRANSACTION;  -- 作用：开启事务，把后续一组写操作作为整体处理
SELECT account_id, provider, account_name  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
FROM dbo.UpstreamAccount  -- 作用：指定当前 SELECT 查询的数据来源
WHERE account_name = N'CRUD-临时账号';  -- 作用：限定本次查询或修改只作用于满足条件的目标记录


-- =========================
-- UpstreamAccount 数据写入
-- =========================
-- 这一批语句用于填充 UpstreamAccount；固定 ID 保证后续外键引用稳定。
INSERT INTO dbo.UpstreamAccount  -- 作用：向 UpstreamAccount 表插入样例或演示数据
    (provider, account_name, api_key, total_quota, used_quota, safety_threshold, status)
VALUES  -- 作用：开始给出 INSERT 对应的字段值
    ('Other', N'CRUD-临时账号', N'DEMO_NOT_A_REAL_API_KEY_CRUD', 100000, 0, 10000, 'active');  -- 作用：写入当前一行样例数据，字段顺序与本批 INSERT 列表一致

DECLARE @demo_account_id INT = SCOPE_IDENTITY();  -- 作用：声明局部变量，保存刚插入记录的主键供后续复用


-- =========================
-- Inventory 数据写入
-- =========================
-- 这一批语句用于填充 Inventory；固定 ID 保证后续外键引用稳定。
INSERT INTO dbo.Inventory (account_id, current_quota)  -- 作用：向 Inventory 表插入样例或演示数据
VALUES (@demo_account_id, 100000);  -- 作用：开始给出 INSERT 对应的字段值

SELECT inventory_id, account_id, current_quota  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
FROM dbo.Inventory  -- 作用：指定当前 SELECT 查询的数据来源
WHERE account_id = @demo_account_id;  -- 作用：限定本次查询或修改只作用于满足条件的目标记录

UPDATE dbo.Inventory  -- 作用：修改 Inventory 表中满足 WHERE 条件的记录
SET current_quota = current_quota - 1000,
    last_updated_at = SYSDATETIME()
WHERE account_id = @demo_account_id;  -- 作用：限定本次查询或修改只作用于满足条件的目标记录

SELECT inventory_id, account_id, current_quota  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
FROM dbo.Inventory  -- 作用：指定当前 SELECT 查询的数据来源
WHERE account_id = @demo_account_id;  -- 作用：限定本次查询或修改只作用于满足条件的目标记录

DELETE FROM dbo.Inventory  -- 作用：删除 Inventory 表中满足 WHERE 条件的演示记录
WHERE account_id = @demo_account_id;  -- 作用：限定本次查询或修改只作用于满足条件的目标记录
DELETE FROM dbo.UpstreamAccount  -- 作用：删除 UpstreamAccount 表中满足 WHERE 条件的演示记录
WHERE account_id = @demo_account_id;  -- 作用：限定本次查询或修改只作用于满足条件的目标记录

SELECT account_id, provider, account_name  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
FROM dbo.UpstreamAccount  -- 作用：指定当前 SELECT 查询的数据来源
WHERE account_id = @demo_account_id;  -- 作用：限定本次查询或修改只作用于满足条件的目标记录
ROLLBACK TRANSACTION;  -- 作用：回滚本组 CRUD 演示，恢复基础样例数据
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

PRINT N'=== C. Orders CRUD ===';  -- 作用：输出当前演示章节标题，便于区分不同 CRUD 段
BEGIN TRANSACTION;  -- 作用：开启事务，把后续一组写操作作为整体处理
SELECT order_id, user_id, total_amount, total_tokens, status  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
FROM dbo.Orders  -- 作用：指定当前 SELECT 查询的数据来源
WHERE order_id = -1;  -- 作用：限定本次查询或修改只作用于满足条件的目标记录

SET IDENTITY_INSERT dbo.Orders ON;  -- 作用：允许显式写入 IDENTITY 主键，保持生成器给出的固定 ID

-- =========================
-- Orders 数据写入
-- =========================
-- 这一批语句用于填充 Orders；固定 ID 保证后续外键引用稳定。
INSERT INTO dbo.Orders  -- 作用：向 Orders 表插入样例或演示数据
    (order_id, user_id, total_amount, total_tokens, status, created_at, paid_at)
VALUES  -- 作用：开始给出 INSERT 对应的字段值
    (-1, 1, 6.90, 100000, 'pending', '2026-09-23 10:00:00', NULL);  -- 作用：写入当前一行样例数据，字段顺序与本批 INSERT 列表一致
SET IDENTITY_INSERT dbo.Orders OFF;  -- 作用：恢复 IDENTITY 自动编号

SET IDENTITY_INSERT dbo.OrderDetails ON;  -- 作用：允许显式写入 IDENTITY 主键，保持生成器给出的固定 ID

-- =========================
-- OrderDetails 数据写入
-- =========================
-- 这一批语句用于填充 OrderDetails；固定 ID 保证后续外键引用稳定。
INSERT INTO dbo.OrderDetails  -- 作用：向 OrderDetails 表插入样例或演示数据
    (detail_id, order_id, product_id, quantity, unit_price, subtotal, tokens_per_unit, total_tokens)
VALUES  -- 作用：开始给出 INSERT 对应的字段值
    (-1, -1, 2, 1, 6.90, 6.90, 100000, 100000);  -- 作用：写入当前一行样例数据，字段顺序与本批 INSERT 列表一致
SET IDENTITY_INSERT dbo.OrderDetails OFF;  -- 作用：恢复 IDENTITY 自动编号

SELECT o.order_id, o.user_id, o.total_amount, o.total_tokens, o.status,  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
       d.product_id, d.quantity, d.subtotal
FROM dbo.Orders AS o  -- 作用：指定当前 SELECT 查询的数据来源
JOIN dbo.OrderDetails AS d ON d.order_id = o.order_id  -- 作用：按外键或业务键关联另一张表
WHERE o.order_id = -1;  -- 作用：限定本次查询或修改只作用于满足条件的目标记录

UPDATE dbo.Orders  -- 作用：修改 Orders 表中满足 WHERE 条件的记录
SET status = 'paid', paid_at = '2026-09-23 10:05:00'
WHERE order_id = -1;  -- 作用：限定本次查询或修改只作用于满足条件的目标记录

SELECT order_id, user_id, total_amount, total_tokens, status, paid_at  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
FROM dbo.Orders  -- 作用：指定当前 SELECT 查询的数据来源
WHERE order_id = -1;  -- 作用：限定本次查询或修改只作用于满足条件的目标记录

DELETE FROM dbo.OrderDetails WHERE order_id = -1;  -- 作用：删除 OrderDetails 表中满足 WHERE 条件的演示记录
DELETE FROM dbo.Orders WHERE order_id = -1;  -- 作用：删除 Orders 表中满足 WHERE 条件的演示记录

SELECT order_id, user_id, total_amount, total_tokens, status  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
FROM dbo.Orders  -- 作用：指定当前 SELECT 查询的数据来源
WHERE order_id = -1;  -- 作用：限定本次查询或修改只作用于满足条件的目标记录
ROLLBACK TRANSACTION;  -- 作用：回滚本组 CRUD 演示，恢复基础样例数据
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

PRINT N'=== D. Typical read queries for product / inventory / order ===';  -- 作用：输出当前演示章节标题，便于区分不同 CRUD 段
SELECT TOP (10)  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
    product_id, name, model_provider, token_amount, price, status
FROM dbo.Products  -- 作用：指定当前 SELECT 查询的数据来源
ORDER BY product_id;  -- 作用：按指定字段排序，让结果更容易阅读和复核

SELECT
    i.inventory_id, a.provider, a.account_name, i.current_quota,
    a.safety_threshold, a.status
FROM dbo.Inventory AS i  -- 作用：指定当前 SELECT 查询的数据来源
JOIN dbo.UpstreamAccount AS a ON a.account_id = i.account_id  -- 作用：按外键或业务键关联另一张表
ORDER BY i.current_quota;  -- 作用：按指定字段排序，让结果更容易阅读和复核

SELECT TOP (10)  -- 作用：读取并展示当前目标数据，用于观察或验证执行结果
    o.order_id, u.username, o.status, o.total_amount, o.total_tokens,
    COUNT(d.detail_id) AS detail_count
FROM dbo.Orders AS o  -- 作用：指定当前 SELECT 查询的数据来源
JOIN dbo.Users AS u ON u.user_id = o.user_id  -- 作用：按外键或业务键关联另一张表
JOIN dbo.OrderDetails AS d ON d.order_id = o.order_id  -- 作用：按外键或业务键关联另一张表
GROUP BY o.order_id, u.username, o.status, o.total_amount, o.total_tokens  -- 作用：按指定字段分组，为聚合统计准备分组粒度
ORDER BY o.order_id;  -- 作用：按指定字段排序，让结果更容易阅读和复核
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO
