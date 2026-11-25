-- Week 5 independent schema and business-rule review. READ ONLY.
SET NOCOUNT ON;
PRINT 'REVIEW-01 table / FK metadata';
SELECT COUNT(*) AS tables FROM sys.tables WHERE is_ms_shipped=0;
SELECT fk.name, OBJECT_NAME(fk.parent_object_id) AS child_table,
       childcol.name AS child_column, childcol.is_nullable,
       OBJECT_NAME(fk.referenced_object_id) AS parent_table,
       parentcol.name AS parent_column, fk.is_disabled, fk.is_not_trusted
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fc ON fc.constraint_object_id=fk.object_id
JOIN sys.columns childcol ON childcol.object_id=fc.parent_object_id AND childcol.column_id=fc.parent_column_id
JOIN sys.columns parentcol ON parentcol.object_id=fc.referenced_object_id AND parentcol.column_id=fc.referenced_column_id
ORDER BY fk.name,fc.constraint_column_id;
PRINT 'REVIEW-02 PK, UK candidates';
SELECT OBJECT_NAME(k.parent_object_id) AS table_name, k.name AS key_name, k.type AS key_type,
       STRING_AGG(c.name, ',') WITHIN GROUP (ORDER BY ic.key_ordinal) AS key_columns
FROM sys.key_constraints k
JOIN sys.index_columns ic ON ic.object_id=k.parent_object_id AND ic.index_id=k.unique_index_id AND ic.key_ordinal>0
JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
GROUP BY k.parent_object_id,k.name,k.type ORDER BY table_name,key_type,key_name;
PRINT 'REVIEW-03 domain checks';
SELECT 'orders_without_details' AS metric,COUNT(*) AS n FROM dbo.Orders o
 WHERE NOT EXISTS (SELECT 1 FROM dbo.OrderDetails d WHERE d.order_id=o.order_id)
UNION ALL SELECT 'accounts_without_inventory',COUNT(*) FROM dbo.UpstreamAccount a
 WHERE NOT EXISTS (SELECT 1 FROM dbo.Inventory i WHERE i.account_id=a.account_id)
UNION ALL SELECT 'same_product_repeated_lines',COUNT(*) FROM (
 SELECT order_id,product_id FROM dbo.OrderDetails GROUP BY order_id,product_id HAVING COUNT(*)>1) x
UNION ALL SELECT 'provider_mismatch',COUNT(*) FROM dbo.TokenUsageLogs l
 JOIN dbo.Products p ON p.product_id=l.product_id JOIN dbo.UpstreamAccount a ON a.account_id=l.account_id WHERE p.model_provider<>a.provider
UNION ALL SELECT 'order_header_mismatch',COUNT(*) FROM dbo.Orders o
 OUTER APPLY (SELECT SUM(d.subtotal) AS amount,SUM(d.total_tokens) AS tokens FROM dbo.OrderDetails d WHERE d.order_id=o.order_id) x
 WHERE x.amount IS NULL OR o.total_amount<>x.amount OR o.total_tokens<>x.tokens
UNION ALL SELECT 'inventory_quota_mismatch',COUNT(*) FROM dbo.Inventory i
 JOIN dbo.UpstreamAccount a ON a.account_id=i.account_id WHERE i.current_quota<>a.total_quota-a.used_quota;
PRINT 'REVIEW-04 weak reference types (no sensitive column values)';
SELECT 'InventoryLog' AS table_name,COALESCE(reference_type,'(NULL)') AS type_value,
       CASE WHEN reference_id IS NULL THEN 'ID_NULL' ELSE 'ID_SET' END AS id_state,COUNT(*) AS n
FROM dbo.InventoryLog GROUP BY reference_type,CASE WHEN reference_id IS NULL THEN 'ID_NULL' ELSE 'ID_SET' END
UNION ALL
SELECT 'ExceptionLog',COALESCE(related_table,'(NULL)'),CASE WHEN related_id IS NULL THEN 'ID_NULL' ELSE 'ID_SET' END,COUNT(*)
FROM dbo.ExceptionLog GROUP BY related_table,CASE WHEN related_id IS NULL THEN 'ID_NULL' ELSE 'ID_SET' END
ORDER BY table_name,type_value,id_state;
