-- Week 3 / 03_crud_demo.sql
-- Each section shows SELECT before/after. Changes are rolled back so the base dataset remains reproducible.

USE [TokenHubDB_Week3];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

PRINT N'=== A. Products CRUD ===';
BEGIN TRANSACTION;
SELECT product_id, name, price, status
FROM dbo.Products
WHERE name = N'CRUD演示临时套餐';

INSERT INTO dbo.Products
    (name, description, price, model_provider, token_amount, required_upstream_tokens, status)
VALUES
    (N'CRUD演示临时套餐', N'仅用于第三周 CRUD 演示', 9.90, 'Other', 123456, 150000, 'active');

SELECT product_id, name, price, status
FROM dbo.Products
WHERE name = N'CRUD演示临时套餐';

UPDATE dbo.Products
SET price = 12.90, status = 'inactive'
WHERE name = N'CRUD演示临时套餐';

SELECT product_id, name, price, status
FROM dbo.Products
WHERE name = N'CRUD演示临时套餐';

DELETE FROM dbo.Products
WHERE name = N'CRUD演示临时套餐';

SELECT product_id, name, price, status
FROM dbo.Products
WHERE name = N'CRUD演示临时套餐';
ROLLBACK TRANSACTION;
GO

PRINT N'=== B. Inventory CRUD ===';
BEGIN TRANSACTION;
SELECT account_id, provider, account_name
FROM dbo.UpstreamAccount
WHERE account_name = N'CRUD-临时账号';

INSERT INTO dbo.UpstreamAccount
    (provider, account_name, api_key, total_quota, used_quota, safety_threshold, status)
VALUES
    ('Other', N'CRUD-临时账号', N'DEMO_NOT_A_REAL_API_KEY_CRUD', 100000, 0, 10000, 'active');

DECLARE @demo_account_id INT = SCOPE_IDENTITY();

INSERT INTO dbo.Inventory (account_id, current_quota)
VALUES (@demo_account_id, 100000);

SELECT inventory_id, account_id, current_quota
FROM dbo.Inventory
WHERE account_id = @demo_account_id;

UPDATE dbo.Inventory
SET current_quota = current_quota - 1000,
    last_updated_at = SYSDATETIME()
WHERE account_id = @demo_account_id;

SELECT inventory_id, account_id, current_quota
FROM dbo.Inventory
WHERE account_id = @demo_account_id;

DELETE FROM dbo.Inventory
WHERE account_id = @demo_account_id;
DELETE FROM dbo.UpstreamAccount
WHERE account_id = @demo_account_id;

SELECT account_id, provider, account_name
FROM dbo.UpstreamAccount
WHERE account_id = @demo_account_id;
ROLLBACK TRANSACTION;
GO

PRINT N'=== C. Orders CRUD ===';
BEGIN TRANSACTION;
SELECT order_id, user_id, total_amount, total_tokens, status
FROM dbo.Orders
WHERE order_id = -1;

SET IDENTITY_INSERT dbo.Orders ON;
INSERT INTO dbo.Orders
    (order_id, user_id, total_amount, total_tokens, status, created_at, paid_at)
VALUES
    (-1, 1, 6.90, 100000, 'pending', '2026-09-23 10:00:00', NULL);
SET IDENTITY_INSERT dbo.Orders OFF;

SET IDENTITY_INSERT dbo.OrderDetails ON;
INSERT INTO dbo.OrderDetails
    (detail_id, order_id, product_id, quantity, unit_price, subtotal, tokens_per_unit, total_tokens)
VALUES
    (-1, -1, 2, 1, 6.90, 6.90, 100000, 100000);
SET IDENTITY_INSERT dbo.OrderDetails OFF;

SELECT o.order_id, o.user_id, o.total_amount, o.total_tokens, o.status,
       d.product_id, d.quantity, d.subtotal
FROM dbo.Orders AS o
JOIN dbo.OrderDetails AS d ON d.order_id = o.order_id
WHERE o.order_id = -1;

UPDATE dbo.Orders
SET status = 'paid', paid_at = '2026-09-23 10:05:00'
WHERE order_id = -1;

SELECT order_id, user_id, total_amount, total_tokens, status, paid_at
FROM dbo.Orders
WHERE order_id = -1;

DELETE FROM dbo.OrderDetails WHERE order_id = -1;
DELETE FROM dbo.Orders WHERE order_id = -1;

SELECT order_id, user_id, total_amount, total_tokens, status
FROM dbo.Orders
WHERE order_id = -1;
ROLLBACK TRANSACTION;
GO

PRINT N'=== D. Typical read queries for product / inventory / order ===';
SELECT TOP (10)
    product_id, name, model_provider, token_amount, price, status
FROM dbo.Products
ORDER BY product_id;

SELECT
    i.inventory_id, a.provider, a.account_name, i.current_quota,
    a.safety_threshold, a.status
FROM dbo.Inventory AS i
JOIN dbo.UpstreamAccount AS a ON a.account_id = i.account_id
ORDER BY i.current_quota;

SELECT TOP (10)
    o.order_id, u.username, o.status, o.total_amount, o.total_tokens,
    COUNT(d.detail_id) AS detail_count
FROM dbo.Orders AS o
JOIN dbo.Users AS u ON u.user_id = o.user_id
JOIN dbo.OrderDetails AS d ON d.order_id = o.order_id
GROUP BY o.order_id, u.username, o.status, o.total_amount, o.total_tokens
ORDER BY o.order_id;
GO
