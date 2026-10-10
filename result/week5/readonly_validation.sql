-- Week 5: read-only ER validation for the existing TokenHubDB_v01_A.
-- No DDL, DML, temporary tables, EXEC, metadata secret values, or credentials.
-- Run with Windows auth: sqlcmd -S localhost\SQLEXPRESS -d TokenHubDB_v01_A -E -C -b -W -i readonly_validation.sql
SET NOCOUNT ON;
PRINT 'W5-01 current database and schema counts';
SELECT DB_NAME() AS database_name, COUNT(*) AS business_tables
FROM sys.tables WHERE is_ms_shipped=0;
SELECT COUNT(*) AS active_foreign_keys
FROM sys.foreign_keys WHERE is_disabled=0;
SELECT COUNT(*) AS formula_payment_checks
FROM sys.check_constraints
WHERE name IN ('CK_OrderDetails_subtotal_formula',
               'CK_OrderDetails_tokens_formula','CK_Orders_payment_time');
PRINT 'W5-02 order relationship checks';
SELECT COUNT(*) AS orders FROM dbo.Orders;
SELECT COUNT(*) AS order_details FROM dbo.OrderDetails;
SELECT COUNT(*) AS orders_with_multiple_details FROM
    (SELECT order_id FROM dbo.OrderDetails GROUP BY order_id HAVING COUNT(*)>1) AS x;
SELECT TOP (5) o.order_id, COUNT(*) AS detail_lines,
       COUNT(DISTINCT d.product_id) AS distinct_products
FROM dbo.Orders o JOIN dbo.OrderDetails d ON d.order_id=o.order_id
GROUP BY o.order_id HAVING COUNT(*)>1
ORDER BY COUNT(*) DESC,o.order_id;
SELECT COUNT(*) AS orders_without_details FROM dbo.Orders o
WHERE NOT EXISTS(SELECT 1 FROM dbo.OrderDetails d WHERE d.order_id=o.order_id);
SELECT COUNT(*) AS header_detail_mismatch FROM dbo.Orders o
LEFT JOIN (
    SELECT order_id,SUM(subtotal) AS amount,SUM(total_tokens) AS tokens
    FROM dbo.OrderDetails GROUP BY order_id
) d ON d.order_id=o.order_id
WHERE d.order_id IS NULL OR o.total_amount<>d.amount OR o.total_tokens<>d.tokens;
PRINT 'W5-03 member and guest participation';
SELECT COUNT(DISTINCT user_id) AS members_with_orders FROM dbo.Orders;
SELECT COUNT(*) AS orders_with_nonexistent_members FROM dbo.Orders o
WHERE NOT EXISTS(SELECT 1 FROM dbo.Users u WHERE u.user_id=o.user_id);
PRINT 'W5-04 upstream account, inventory and usage';
SELECT COUNT(*) AS accounts_without_inventory FROM dbo.UpstreamAccount a
WHERE NOT EXISTS(SELECT 1 FROM dbo.Inventory i WHERE i.account_id=a.account_id);
SELECT COUNT(*) AS inventory_quota_mismatches
FROM dbo.Inventory i JOIN dbo.UpstreamAccount a ON a.account_id=i.account_id
WHERE i.current_quota<>a.total_quota-a.used_quota;
SELECT a.provider,COUNT(*) AS account_count, SUM(i.current_quota) AS total_remaining,
SUM(CASE WHEN i.current_quota<a.safety_threshold THEN 1 ELSE 0 END) AS below_safety_threshold
FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id
GROUP BY a.provider ORDER BY a.provider;
SELECT COUNT(*) AS provider_mismatched_usage
FROM dbo.TokenUsageLogs l
JOIN dbo.Products p ON p.product_id=l.product_id
JOIN dbo.UpstreamAccount a ON a.account_id=l.account_id
WHERE p.model_provider<>a.provider;
PRINT 'W5-05 optional employee FKs, and FK metadata count';
SELECT COUNT(*) AS nullable_operator_rows FROM dbo.InventoryLog WHERE operator_id IS NULL;
SELECT COUNT(*) AS nullable_assignee_rows FROM dbo.RestockTask WHERE assigned_to IS NULL;
SELECT COUNT(*) AS nullable_handler_rows FROM dbo.ExceptionLog WHERE handled_by IS NULL;
SELECT OBJECT_NAME(parent_object_id) AS child_table, name AS fk_constraint,
       OBJECT_NAME(referenced_object_id) AS parent_table
FROM sys.foreign_keys
WHERE is_disabled=0
ORDER BY child_table,fk_constraint;
