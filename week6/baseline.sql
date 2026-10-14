-- Week 6 semantic baseline. Only read non-sensitive business columns and metadata.
-- Run with -d on the SOURCE and on the untouched RESTORED COPY, -h -1 -W -w 65535.
SET NOCOUNT ON;
SELECT CONCAT('COUNTS|',
 (SELECT COUNT_BIG(*) FROM dbo.Roles),'|',(SELECT COUNT_BIG(*) FROM dbo.Users),'|',
 (SELECT COUNT_BIG(*) FROM dbo.Products),'|',(SELECT COUNT_BIG(*) FROM dbo.UpstreamAccount),'|',
 (SELECT COUNT_BIG(*) FROM dbo.Inventory),'|',(SELECT COUNT_BIG(*) FROM dbo.Employees),'|',
 (SELECT COUNT_BIG(*) FROM dbo.Orders),'|',(SELECT COUNT_BIG(*) FROM dbo.OrderDetails),'|',
 (SELECT COUNT_BIG(*) FROM dbo.InventoryLog),'|',(SELECT COUNT_BIG(*) FROM dbo.TokenBalances),'|',
 (SELECT COUNT_BIG(*) FROM dbo.TokenUsageLogs),'|',(SELECT COUNT_BIG(*) FROM dbo.UsageSummary),'|',
 (SELECT COUNT_BIG(*) FROM dbo.RestockTask),'|',(SELECT COUNT_BIG(*) FROM dbo.ExceptionLog));
SELECT CONCAT('O|',order_id,'|',user_id,'|',status,'|',total_amount,'|',total_tokens,'|',
 CONVERT(varchar(19),created_at,126),'|',COALESCE(CONVERT(varchar(19),paid_at,126),'<NULL>'))
 FROM dbo.Orders ORDER BY order_id;
SELECT CONCAT('D|',detail_id,'|',order_id,'|',product_id,'|',quantity,'|',unit_price,
 '|',subtotal,'|',tokens_per_unit,'|',total_tokens)
 FROM dbo.OrderDetails ORDER BY detail_id;
SELECT CONCAT('S|',p.product_id,'|',COALESCE(SUM(CASE WHEN o.order_id IS NOT NULL THEN d.quantity ELSE 0 END),0),
 '|',COALESCE(SUM(CASE WHEN o.order_id IS NOT NULL THEN d.subtotal ELSE 0 END),0))
 FROM dbo.Products p
 LEFT JOIN dbo.OrderDetails d ON d.product_id=p.product_id
 LEFT JOIN dbo.Orders o ON o.order_id=d.order_id AND o.status='paid'
 GROUP BY p.product_id ORDER BY p.product_id;
SELECT CONCAT('I|',a.account_id,'|',a.provider,'|',a.total_quota,'|',a.used_quota,
 '|',a.safety_threshold,'|',a.status,'|',COALESCE(CONVERT(varchar(19),a.expires_at,126),'<NULL>'),
 '|',COALESCE(CONVERT(varchar(24),i.current_quota),'<NULL>'))
 FROM dbo.UpstreamAccount a LEFT JOIN dbo.Inventory i ON i.account_id=a.account_id ORDER BY a.account_id;
SELECT CONCAT('B|',user_id,'|',model_provider,'|',remaining_tokens)
 FROM dbo.TokenBalances ORDER BY user_id,model_provider;
SELECT CONCAT('SUM|',user_id,'|',product_id,'|',period_type,'|',CONVERT(varchar(10),period_start,23),
 '|',CONVERT(varchar(10),period_end,23),'|',total_tokens_used,'|',total_upstream_consumed,'|',request_count)
 FROM dbo.UsageSummary ORDER BY user_id,product_id,period_type,period_start;
SELECT CONCAT('USAGE|',COUNT_BIG(*),'|',COALESCE(SUM(CONVERT(bigint,tokens_used)),0),
 '|',COALESCE(SUM(CONVERT(bigint,upstream_tokens_consumed)),0))
 FROM dbo.TokenUsageLogs;
SELECT CONCAT('PERMISSION|',p.name COLLATE DATABASE_DEFAULT,'|',
 COALESCE((OBJECT_SCHEMA_NAME(dp.major_id) COLLATE DATABASE_DEFAULT) + '.' + (OBJECT_NAME(dp.major_id) COLLATE DATABASE_DEFAULT),'DATABASE'),
 '|',dp.permission_name COLLATE DATABASE_DEFAULT,'|',dp.state_desc COLLATE DATABASE_DEFAULT)
 FROM sys.database_permissions dp
 JOIN sys.database_principals p ON p.principal_id=dp.grantee_principal_id
 WHERE p.name IN ('hub_manager','hub_staff','hub_customer','hub_guest')
 ORDER BY p.name,dp.major_id,dp.permission_name,dp.state_desc;
SELECT CONCAT('ROLE|',name) FROM sys.database_principals
 WHERE name IN ('hub_manager','hub_staff','hub_customer','hub_guest') ORDER BY name;
