-- Week 6 FD / data quality probes. Read-only; output contains no credentials or PII.
SET NOCOUNT ON;
SELECT 'schema_table_count' AS check_name,COUNT(*) AS n FROM sys.tables WHERE is_ms_shipped=0;
SELECT 'schema_fk_count' AS check_name,COUNT(*) AS n FROM sys.foreign_keys WHERE is_disabled=0;
SELECT 'detail_subtotal_formula_bad' AS check_name,COUNT_BIG(*) AS n FROM dbo.OrderDetails
 WHERE subtotal <> CONVERT(decimal(19,2),quantity)*unit_price;
SELECT 'detail_tokens_formula_bad' AS check_name,COUNT_BIG(*) AS n FROM dbo.OrderDetails
 WHERE total_tokens <> CONVERT(bigint,quantity)*tokens_per_unit;
SELECT 'duplicate_order_product_key' AS check_name,COUNT(*) AS n FROM
 (SELECT order_id,product_id FROM dbo.OrderDetails GROUP BY order_id,product_id HAVING COUNT_BIG(*)>1) q;
SELECT 'summary_period_multiple_ends_for_same_start' AS check_name,COUNT(*) AS n FROM
 (SELECT period_type,period_start FROM dbo.UsageSummary
  GROUP BY period_type,period_start HAVING COUNT(DISTINCT period_end)>1) q;
SELECT period_type, COUNT(*) AS n, MIN(DATEDIFF(day,period_start,period_end)) AS min_days,
 MAX(DATEDIFF(day,period_start,period_end)) AS max_days FROM dbo.UsageSummary
 GROUP BY period_type ORDER BY period_type;
SELECT 'order_header_amount_mismatch' AS check_name,COUNT_BIG(*) AS n FROM dbo.Orders o
 LEFT JOIN (SELECT order_id,SUM(subtotal) amount,SUM(total_tokens) tokens FROM dbo.OrderDetails GROUP BY order_id) x
 ON x.order_id=o.order_id WHERE x.order_id IS NULL OR x.amount<>o.total_amount OR x.tokens<>o.total_tokens;
SELECT 'inventory_snapshot_mismatch' AS check_name,COUNT_BIG(*) AS n FROM dbo.Inventory i
 JOIN dbo.UpstreamAccount u ON u.account_id=i.account_id WHERE i.current_quota<>u.total_quota-u.used_quota;
SELECT 'roles_count' AS check_name,COUNT_BIG(*) AS n FROM dbo.Roles;
SELECT 'restock_task_created_nullable' AS check_name,COUNT(*) AS n
 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.RestockTask') AND name='created_by' AND is_nullable=1;
SELECT 'exception_polymorphic_reference_count' AS check_name,COUNT_BIG(*) AS n
 FROM dbo.ExceptionLog WHERE related_table IS NOT NULL AND related_id IS NOT NULL;
