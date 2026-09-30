USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW dbo.v_OrderDetail AS
SELECT o.order_id,o.user_id,u.username,o.status,o.created_at,o.paid_at,
       d.detail_id,p.product_id,p.name AS product_name,p.model_provider,
       d.quantity,d.unit_price,d.subtotal,d.total_tokens
FROM dbo.Orders o JOIN dbo.Users u ON u.user_id=o.user_id
JOIN dbo.OrderDetails d ON d.order_id=o.order_id
JOIN dbo.Products p ON p.product_id=d.product_id;
GO

CREATE OR ALTER VIEW dbo.v_ProductSales AS
WITH s AS (
    SELECT d.product_id,SUM(CAST(d.quantity AS BIGINT)) AS units_sold,
           SUM(d.subtotal) AS revenue,SUM(d.total_tokens) AS tokens_sold
    FROM dbo.OrderDetails d JOIN dbo.Orders o ON o.order_id=d.order_id
    WHERE o.status='paid' GROUP BY d.product_id
)
SELECT p.product_id,p.name,p.model_provider,
       COALESCE(s.units_sold,0) AS units_sold,
       COALESCE(s.revenue,0) AS revenue,COALESCE(s.tokens_sold,0) AS tokens_sold
FROM dbo.Products p LEFT JOIN s ON s.product_id=p.product_id;
GO
CREATE OR ALTER VIEW dbo.v_MemberSpending AS
SELECT u.user_id,u.username,COUNT(o.order_id) AS paid_orders,
       COALESCE(SUM(o.total_amount),0) AS paid_amount,
       COALESCE(SUM(o.total_tokens),0) AS paid_tokens
FROM dbo.Users u LEFT JOIN dbo.Orders o
  ON o.user_id=u.user_id AND o.status='paid'
GROUP BY u.user_id,u.username;
GO

CREATE OR ALTER VIEW dbo.v_InventoryStatus AS
SELECT a.account_id,a.provider,a.account_name,a.status,
       i.current_quota,a.safety_threshold,a.expires_at,
       CAST('2026-09-22T23:59:59' AS DATETIME2(0)) AS as_of_time,
       CASE WHEN a.status<>'active' THEN a.status
            WHEN a.expires_at<='2026-09-22T23:59:59' THEN 'expired'
            WHEN i.current_quota<a.safety_threshold THEN 'low'
            ELSE 'normal' END AS stock_state
FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id;
GO

CREATE OR ALTER VIEW dbo.v_ProductCatalog AS
SELECT product_id,name,description,price,model_provider,token_amount
FROM dbo.Products WHERE status='active';
GO

CREATE OR ALTER VIEW dbo.v_MyOrders AS
SELECT order_id,user_id,total_amount,total_tokens,status,created_at,paid_at
FROM dbo.Orders
WHERE USER_NAME()=CONCAT(N'hub_user_',CONVERT(NVARCHAR(11),user_id));
GO
CREATE OR ALTER VIEW dbo.v_MyBalances AS
SELECT balance_id,user_id,model_provider,remaining_tokens,updated_at
FROM dbo.TokenBalances
WHERE USER_NAME()=CONCAT(N'hub_user_',CONVERT(NVARCHAR(11),user_id));
GO

CREATE OR ALTER VIEW dbo.v_MyUsage AS
SELECT log_id,user_id,product_id,tokens_used,api_endpoint,used_at
FROM dbo.TokenUsageLogs
WHERE USER_NAME()=CONCAT(N'hub_user_',CONVERT(NVARCHAR(11),user_id));
GO

CREATE OR ALTER VIEW dbo.v_StaffOrderQueue AS
SELECT order_id,user_id,status,created_at
FROM dbo.Orders WHERE status IN ('pending','cancelled')
WITH CHECK OPTION;
GO

PRINT N'V01 v_OrderDetail';
SELECT * FROM dbo.v_OrderDetail ORDER BY order_id,detail_id;
PRINT N'V02 v_ProductSales';
SELECT * FROM dbo.v_ProductSales ORDER BY product_id;
PRINT N'V03 v_MemberSpending';
SELECT * FROM dbo.v_MemberSpending ORDER BY user_id;
PRINT N'V04 v_InventoryStatus';
SELECT * FROM dbo.v_InventoryStatus ORDER BY account_id;
GO
