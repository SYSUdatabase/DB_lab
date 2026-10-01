USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT N'Q01 Order details';
SELECT o.order_id, o.user_id, u.username, o.status, o.created_at,
       d.detail_id, p.product_id, p.name AS product_name,
       d.quantity, d.unit_price, d.subtotal, d.total_tokens
FROM dbo.Orders o
JOIN dbo.Users u ON u.user_id=o.user_id
JOIN dbo.OrderDetails d ON d.order_id=o.order_id
JOIN dbo.Products p ON p.product_id=d.product_id
ORDER BY o.order_id, d.detail_id;
GO

PRINT N'Q02 Paid product sales';
WITH s AS (
    SELECT d.product_id, SUM(CAST(d.quantity AS BIGINT)) AS units_sold,
           SUM(d.subtotal) AS revenue, SUM(d.total_tokens) AS tokens_sold
    FROM dbo.OrderDetails d JOIN dbo.Orders o ON o.order_id=d.order_id
    WHERE o.status='paid' GROUP BY d.product_id
)
SELECT p.product_id, p.name, p.model_provider,
       COALESCE(s.units_sold,0) AS units_sold,
       COALESCE(s.revenue,0) AS revenue, COALESCE(s.tokens_sold,0) AS tokens_sold
FROM dbo.Products p LEFT JOIN s ON s.product_id=p.product_id
ORDER BY revenue DESC, p.product_id;
GO
PRINT N'Q03 All member spending';
SELECT u.user_id,u.username,COUNT(o.order_id) AS paid_orders,
       COALESCE(SUM(o.total_amount),0) AS paid_amount
FROM dbo.Users u
LEFT JOIN dbo.Orders o ON o.user_id=u.user_id AND o.status='paid'
GROUP BY u.user_id,u.username ORDER BY u.user_id;
GO

PRINT N'Q04 Members spending at least 100';
SELECT u.user_id,u.username,SUM(o.total_amount) AS paid_amount
FROM dbo.Users u JOIN dbo.Orders o ON o.user_id=u.user_id
WHERE o.status='paid'
GROUP BY u.user_id,u.username HAVING SUM(o.total_amount)>=100
ORDER BY paid_amount DESC,u.user_id;
GO

PRINT N'Q05 Members without paid orders';
SELECT u.user_id,u.username FROM dbo.Users u
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Orders o WHERE o.user_id=u.user_id AND o.status='paid'
) ORDER BY u.user_id;
GO

PRINT N'Q06 Active low quota accounts at sample snapshot';
DECLARE @as_of DATETIME2(0)='2026-09-22T23:59:59';
SELECT COUNT(*) AS low_quota_accounts
FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id
WHERE a.status='active' AND (a.expires_at IS NULL OR a.expires_at>@as_of)
  AND i.current_quota<a.safety_threshold;
SELECT a.account_id,a.provider,a.account_name,i.current_quota,a.safety_threshold
FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id
WHERE a.status='active' AND (a.expires_at IS NULL OR a.expires_at>@as_of)
  AND i.current_quota<a.safety_threshold
ORDER BY a.account_id;
GO
PRINT N'Q07 Usage by provider';
SELECT p.model_provider,COUNT_BIG(*) AS requests,
       SUM(CAST(l.tokens_used AS BIGINT)) AS tokens_used,
       SUM(CAST(l.upstream_tokens_consumed AS BIGINT)) AS upstream_used
FROM dbo.TokenUsageLogs l JOIN dbo.Products p ON p.product_id=l.product_id
GROUP BY p.model_provider ORDER BY p.model_provider;
GO

PRINT N'Q08 Restock task assignment';
SELECT t.task_id,a.account_name,t.status,t.target_amount,t.actual_amount,
       creator.name AS created_by_name,assignee.name AS assigned_to_name
FROM dbo.RestockTask t
JOIN dbo.UpstreamAccount a ON a.account_id=t.account_id
JOIN dbo.Employees creator ON creator.employee_id=t.created_by
LEFT JOIN dbo.Employees assignee ON assignee.employee_id=t.assigned_to
ORDER BY t.task_id;
GO
PRINT N'Q09 Low quota detection with a boundary case inside a rolled-back transaction';
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,
        used_quota,safety_threshold,status,expires_at)
    VALUES('Other',N'Q09低库存边界',N'DEMO_NOT_A_REAL_API_KEY_Q09',1000,900,200,
        'active','2027-12-31');
    DECLARE @probe_account INT=SCOPE_IDENTITY();
    INSERT dbo.Inventory(account_id,current_quota) VALUES(@probe_account,100);
    INSERT dbo.InventoryLog(account_id,change_type,change_amount,reason)
    VALUES(@probe_account,'purchase',1000,N'Q09期初采购'),
          (@probe_account,'consumption',-900,N'Q09消耗至阈值以下');
    SELECT a.account_id,a.provider,a.account_name,i.current_quota,a.safety_threshold,
           v.account_state,v.stock_state,v.quota_headroom
    FROM dbo.UpstreamAccount a
    JOIN dbo.Inventory i ON i.account_id=a.account_id
    JOIN dbo.v_InventoryStatus v ON v.account_id=a.account_id
    WHERE i.current_quota<a.safety_threshold
    ORDER BY a.account_id;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
IF @@TRANCOUNT<>0 THROW 51401,N'Open transaction after Q09',1;
PRINT N'Q09 boundary rows rolled back; baseline data unchanged';
GO
PRINT N'Q10 INNER JOIN versus LEFT JOIN row counts';
WITH paid_product AS (
    SELECT d.product_id
    FROM dbo.OrderDetails d JOIN dbo.Orders o ON o.order_id=d.order_id
    WHERE o.status='paid' GROUP BY d.product_id
)
SELECT 'products INNER JOIN' AS join_type,COUNT(*) AS rows_returned
FROM dbo.Products p JOIN paid_product s ON s.product_id=p.product_id
UNION ALL
SELECT 'products LEFT JOIN',COUNT(*)
FROM dbo.Products p LEFT JOIN paid_product s ON s.product_id=p.product_id
UNION ALL
SELECT 'members INNER JOIN',COUNT(*)
FROM dbo.Users u
JOIN (SELECT DISTINCT user_id FROM dbo.Orders WHERE status='paid') s ON s.user_id=u.user_id
UNION ALL
SELECT 'members LEFT JOIN',COUNT(*)
FROM dbo.Users u
LEFT JOIN (SELECT DISTINCT user_id FROM dbo.Orders WHERE status='paid') s ON s.user_id=u.user_id;
GO
PRINT N'Q11 Usage trend from UsageSummary';
SELECT TOP 14 period_start AS usage_day,
       SUM(total_tokens_used) AS tokens_used,
       SUM(total_upstream_consumed) AS upstream_consumed,
       SUM(request_count) AS requests
FROM dbo.UsageSummary WHERE period_type='daily'
GROUP BY period_start ORDER BY period_start DESC;
SELECT period_start AS month_start,period_end AS month_end,
       SUM(total_tokens_used) AS tokens_used,
       SUM(total_upstream_consumed) AS upstream_consumed,
       SUM(request_count) AS requests
FROM dbo.UsageSummary WHERE period_type='monthly'
GROUP BY period_start,period_end ORDER BY period_start;
GO
PRINT N'Q12 Inventory consumption ranking and movement mix';
SELECT TOP 10 a.account_id,a.provider,a.account_name,
       SUM(CASE WHEN l.change_type='consumption' THEN -l.change_amount ELSE 0 END) AS tokens_consumed,
       SUM(CASE WHEN l.change_type='purchase'    THEN  l.change_amount ELSE 0 END) AS tokens_purchased,
       SUM(CASE WHEN l.change_type='restock'     THEN  l.change_amount ELSE 0 END) AS tokens_restocked,
       COUNT(*) AS movements
FROM dbo.InventoryLog l JOIN dbo.UpstreamAccount a ON a.account_id=l.account_id
GROUP BY a.account_id,a.provider,a.account_name
ORDER BY tokens_consumed DESC;
SELECT change_type,COUNT(*) AS movements,SUM(change_amount) AS net_change
FROM dbo.InventoryLog GROUP BY change_type ORDER BY change_type;
GO
