USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT N'VFY01 Baseline row counts';
DECLARE @expected TABLE(table_name SYSNAME,pk_name SYSNAME,row_count INT);
INSERT @expected VALUES
('Roles','role_id',3),('Users','user_id',40),('Products','product_id',10),
('UpstreamAccount','account_id',8),('Inventory','inventory_id',8),
('Employees','employee_id',6),('Orders','order_id',100),
('OrderDetails','detail_id',184),('InventoryLog','log_id',3012),
('TokenBalances','balance_id',61),('TokenUsageLogs','log_id',3000),
('UsageSummary','summary_id',3394),('RestockTask','task_id',8),
('ExceptionLog','exception_id',15);
DECLARE @table SYSNAME,@expected_count INT,@actual BIGINT,@sql NVARCHAR(MAX);
DECLARE row_counts CURSOR LOCAL FAST_FORWARD FOR SELECT table_name,row_count FROM @expected;
OPEN row_counts;
FETCH NEXT FROM row_counts INTO @table,@expected_count;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @sql=N'SELECT @n=COUNT_BIG(*) FROM dbo.'+QUOTENAME(@table)+N';';
    EXEC sys.sp_executesql @sql,N'@n BIGINT OUTPUT',@n=@actual OUTPUT;
    IF @actual<>@expected_count THROW 51301,N'Baseline row count mismatch',1;
    SELECT @table AS table_name,@actual AS actual_rows,@expected_count AS expected_rows,N'PASS' AS result;
    FETCH NEXT FROM row_counts INTO @table,@expected_count;
END;
CLOSE row_counts;
DEALLOCATE row_counts;
GO
PRINT N'VFY02 Core business totals';
IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>14
    THROW 51310,N'Expected 14 business tables',1;
IF (SELECT COUNT(*) FROM dbo.Orders WHERE status='paid')<>85
 OR (SELECT SUM(total_amount) FROM dbo.Orders WHERE status='paid')<>4228.90
    THROW 51311,N'Paid order count or revenue mismatch',1;
IF (SELECT SUM(total_amount) FROM dbo.Orders)<>4931.00
 OR (SELECT SUM(total_tokens) FROM dbo.Orders)<>108950000
 OR (SELECT SUM(total_tokens) FROM dbo.Orders WHERE status='paid')<>92950000
    THROW 51320,N'Order totals mismatch',1;
IF (SELECT COUNT(*) FROM dbo.OrderDetails d JOIN dbo.Orders o ON o.order_id=d.order_id
     WHERE o.status='paid')<>158
 OR (SELECT SUM(CAST(d.quantity AS BIGINT)) FROM dbo.OrderDetails d
     JOIN dbo.Orders o ON o.order_id=d.order_id WHERE o.status='paid')<>191
    THROW 51321,N'Paid detail count or units mismatch',1;
IF (SELECT SUM(CAST(tokens_used AS BIGINT)) FROM dbo.TokenUsageLogs)<>6040100
 OR (SELECT SUM(CAST(upstream_tokens_consumed AS BIGINT)) FROM dbo.TokenUsageLogs)<>7248120
    THROW 51322,N'Raw usage totals mismatch',1;
IF (SELECT SUM(remaining_tokens) FROM dbo.TokenBalances)<>86909900
    THROW 51312,N'Balance total mismatch',1;
IF (SELECT SUM(current_quota) FROM dbo.Inventory)<>6350000
 OR (SELECT SUM(change_amount) FROM dbo.InventoryLog)<>6350000
    THROW 51323,N'Inventory totals mismatch',1;
PRINT N'PASS VFY02 core business totals';
GO

PRINT N'VFY03 Views, roles and constraints';
IF (SELECT COUNT(*) FROM sys.views WHERE is_ms_shipped=0)<>9
    THROW 51308,N'View count mismatch',1;
IF (SELECT COUNT(*) FROM dbo.v_OrderDetail)<>184
 OR (SELECT COUNT(*) FROM dbo.v_ProductSales)<>10
 OR (SELECT COUNT(*) FROM dbo.v_MemberSpending)<>40
 OR (SELECT COUNT(*) FROM dbo.v_InventoryStatus)<>8
 OR (SELECT COUNT(*) FROM dbo.v_InventoryStatus WHERE stock_state='low')<>0
    THROW 51324,N'Core view row counts mismatch',1;
IF (SELECT SUM(revenue) FROM dbo.v_ProductSales)<>4228.90
 OR (SELECT SUM(units_sold) FROM dbo.v_ProductSales)<>191
 OR (SELECT SUM(tokens_sold) FROM dbo.v_ProductSales)<>92950000
    THROW 51302,N'Product sales mismatch',1;
IF (SELECT COUNT(*) FROM dbo.v_MemberSpending WHERE paid_orders=0)<>14
 OR (SELECT COUNT(*) FROM dbo.v_MemberSpending WHERE paid_amount>=100)<>13
    THROW 51303,N'Member spending mismatch',1;
IF EXISTS(SELECT 1 FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1)
 OR EXISTS(SELECT 1 FROM sys.check_constraints WHERE is_disabled=1 OR is_not_trusted=1)
    THROW 51307,N'Disabled or untrusted constraint',1;
IF (SELECT COUNT(*) FROM sys.database_principals
    WHERE type='R' AND name IN ('hub_manager','hub_staff','hub_customer','hub_guest'))<>4
 OR (SELECT COUNT(*) FROM sys.database_principals
     WHERE type='S' AND name IN ('hub_manager_demo','hub_staff_demo','hub_user_1','hub_user_2','hub_guest_demo'))<>5
    THROW 51325,N'Role or demonstration user missing',1;
IF (SELECT COUNT(*) FROM sys.check_constraints WHERE name IN
    ('CK_OrderDetails_subtotal_formula','CK_OrderDetails_tokens_formula','CK_Orders_payment_time'))<>3
    THROW 51326,N'New cross-column constraints missing',1;
IF @@TRANCOUNT<>0 THROW 51309,N'Open transaction remains',1;
PRINT N'PASS VFY03 views, roles and constraints';
GO

PRINT N'VFY04 UsageSummary aggregate grain';
IF EXISTS (
    SELECT period_type FROM dbo.UsageSummary GROUP BY period_type
    HAVING SUM(total_tokens_used)<>6040100
       OR SUM(total_upstream_consumed)<>7248120 OR SUM(request_count)<>3000
) OR (SELECT COUNT(DISTINCT period_type) FROM dbo.UsageSummary)<>3
    THROW 51304,N'Usage summary grain mismatch',1;
PRINT N'PASS VFY04 usage summary grain';
GO

PRINT N'VFY05 Header/detail and inventory relationships';
IF EXISTS (
    SELECT 1 FROM dbo.Orders o LEFT JOIN (
        SELECT order_id,SUM(subtotal) amount,SUM(total_tokens) tokens
        FROM dbo.OrderDetails GROUP BY order_id
    ) d ON d.order_id=o.order_id
    WHERE d.order_id IS NULL OR o.total_amount<>d.amount OR o.total_tokens<>d.tokens
) THROW 51305,N'Order header/detail mismatch',1;
IF EXISTS (
    SELECT 1 FROM dbo.UpstreamAccount a
    LEFT JOIN dbo.Inventory i ON i.account_id=a.account_id
    LEFT JOIN (SELECT account_id,SUM(change_amount) balance FROM dbo.InventoryLog GROUP BY account_id) l
      ON l.account_id=a.account_id
    WHERE i.account_id IS NULL OR l.account_id IS NULL
       OR i.current_quota<>a.total_quota-a.used_quota OR i.current_quota<>l.balance
) THROW 51306,N'Account/inventory/log mismatch',1;
PRINT N'PASS VFY05 relationship checks';
GO
PRINT N'VFY06 Exact member identity sets';
DECLARE @expected_no_paid TABLE(id INT PRIMARY KEY);
INSERT @expected_no_paid(id) VALUES(9),(16),(19),(22),(23),(25),(28),(29),(31),(36),(37),(38),(39),(40);
DECLARE @expected_high TABLE(id INT PRIMARY KEY);
INSERT @expected_high(id) VALUES(1),(2),(3),(5),(8),(11),(12),(15),(17),(18),(24),(33),(35);
IF EXISTS(SELECT user_id FROM dbo.v_MemberSpending WHERE paid_orders=0 EXCEPT SELECT id FROM @expected_no_paid)
 OR EXISTS(SELECT id FROM @expected_no_paid EXCEPT SELECT user_id FROM dbo.v_MemberSpending WHERE paid_orders=0)
 OR EXISTS(SELECT user_id FROM dbo.v_MemberSpending WHERE paid_amount>=100 EXCEPT SELECT id FROM @expected_high)
 OR EXISTS(SELECT id FROM @expected_high EXCEPT SELECT user_id FROM dbo.v_MemberSpending WHERE paid_amount>=100)
    THROW 51327,N'Member identity set mismatch',1;
PRINT N'PASS VFY06 exact member identity sets';
GO

PRINT N'VFY07 Product view row-by-row';
SELECT p.product_id,p.name,p.model_provider,
       COALESCE(x.units_sold,0) AS units_sold,
       COALESCE(x.revenue,0) AS revenue,COALESCE(x.tokens_sold,0) AS tokens_sold
INTO #ProductReference
FROM dbo.Products p OUTER APPLY(
    SELECT SUM(CAST(d.quantity AS BIGINT)) AS units_sold,
           SUM(d.subtotal) AS revenue,SUM(d.total_tokens) AS tokens_sold
    FROM dbo.OrderDetails d
    WHERE d.product_id=p.product_id AND EXISTS(
        SELECT 1 FROM dbo.Orders o WHERE o.order_id=d.order_id AND o.status='paid'
    )
) x;
IF EXISTS(SELECT * FROM #ProductReference EXCEPT SELECT * FROM dbo.v_ProductSales)
 OR EXISTS(SELECT * FROM dbo.v_ProductSales EXCEPT SELECT * FROM #ProductReference)
    THROW 51330,N'Product view row differences',1;
DROP TABLE #ProductReference;
PRINT N'PASS VFY07 product view row-by-row';
GO
PRINT N'VFY08 Member view row-by-row';
SELECT u.user_id,u.username,x.paid_orders,
       COALESCE(x.paid_amount,0) AS paid_amount,COALESCE(x.paid_tokens,0) AS paid_tokens
INTO #MemberReference
FROM dbo.Users u OUTER APPLY(
    SELECT COUNT(*) AS paid_orders,SUM(o.total_amount) AS paid_amount,
           SUM(o.total_tokens) AS paid_tokens
    FROM dbo.Orders o WHERE o.user_id=u.user_id AND o.status='paid'
) x;
IF EXISTS(SELECT * FROM #MemberReference EXCEPT SELECT * FROM dbo.v_MemberSpending)
 OR EXISTS(SELECT * FROM dbo.v_MemberSpending EXCEPT SELECT * FROM #MemberReference)
    THROW 51331,N'Member view row differences',1;
DROP TABLE #MemberReference;
PRINT N'PASS VFY08 member view row-by-row';
GO

PRINT N'VFY09 Balance per user/provider';
WITH credits AS(
    SELECT o.user_id,p.model_provider,SUM(d.total_tokens) AS purchased
    FROM dbo.Orders o JOIN dbo.OrderDetails d ON d.order_id=o.order_id
    JOIN dbo.Products p ON p.product_id=d.product_id
    WHERE o.status='paid' GROUP BY o.user_id,p.model_provider
), used AS(
    SELECT l.user_id,p.model_provider,SUM(CAST(l.tokens_used AS BIGINT)) AS consumed
    FROM dbo.TokenUsageLogs l JOIN dbo.Products p ON p.product_id=l.product_id
    GROUP BY l.user_id,p.model_provider
)
SELECT COALESCE(c.user_id,u.user_id) AS user_id,
       COALESCE(c.model_provider,u.model_provider) AS model_provider,
       COALESCE(c.purchased,0)-COALESCE(u.consumed,0) AS remaining_tokens
INTO #BalanceReference
FROM credits c FULL JOIN used u
 ON u.user_id=c.user_id AND u.model_provider=c.model_provider;
IF EXISTS(SELECT * FROM #BalanceReference
          EXCEPT SELECT user_id,model_provider,remaining_tokens FROM dbo.TokenBalances)
 OR EXISTS(SELECT user_id,model_provider,remaining_tokens FROM dbo.TokenBalances
           EXCEPT SELECT * FROM #BalanceReference)
    THROW 51332,N'Balance per-user/provider mismatch',1;
DROP TABLE #BalanceReference;
PRINT N'PASS VFY09 balance reconciliation';
GO
PRINT N'VFY10 UsageSummary per key';
WITH dated AS(
    SELECT l.*,CONVERT(DATE,l.used_at) AS used_date,
      DATEADD(DAY,-(DATEDIFF(DAY,CONVERT(DATE,'19000101'),CONVERT(DATE,l.used_at))%7),
              CONVERT(DATE,l.used_at)) AS week_start
    FROM dbo.TokenUsageLogs l
)
SELECT d.user_id,d.product_id,p.period_type,p.period_start,p.period_end,
       SUM(CAST(d.tokens_used AS BIGINT)) AS total_tokens_used,
       SUM(CAST(d.upstream_tokens_consumed AS BIGINT)) AS total_upstream_consumed,
       COUNT(*) AS request_count
INTO #SummaryReference
FROM dated d CROSS APPLY(VALUES
    ('daily',d.used_date,d.used_date),
    ('weekly',d.week_start,DATEADD(DAY,6,d.week_start)),
    ('monthly',DATEFROMPARTS(YEAR(d.used_date),MONTH(d.used_date),1),EOMONTH(d.used_date))
) p(period_type,period_start,period_end)
GROUP BY d.user_id,d.product_id,p.period_type,p.period_start,p.period_end;
IF EXISTS(
    SELECT * FROM #SummaryReference EXCEPT
    SELECT user_id,product_id,period_type,period_start,period_end,
           total_tokens_used,total_upstream_consumed,request_count FROM dbo.UsageSummary
) OR EXISTS(
    SELECT user_id,product_id,period_type,period_start,period_end,
           total_tokens_used,total_upstream_consumed,request_count FROM dbo.UsageSummary
    EXCEPT SELECT * FROM #SummaryReference
) THROW 51333,N'Usage summary per-key mismatch',1;
DROP TABLE #SummaryReference;
PRINT N'PASS VFY10 usage summary reconciliation';
GO

PRINT N'VFY11 Boundary positives';
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT dbo.Products(name,price,model_provider,token_amount,required_upstream_tokens)
    VALUES(N'W4零销量边界',1,'Other',910001,910001);
    DECLARE @p INT=SCOPE_IDENTITY();
    IF NOT EXISTS(SELECT 1 FROM dbo.v_ProductSales WHERE product_id=@p
                  AND units_sold=0 AND revenue=0 AND tokens_sold=0)
        THROW 51340,N'Zero-sales product missing',1;
    INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,
      used_quota,safety_threshold,status,expires_at)
    VALUES('Other',N'W4低库存边界',N'DEMO_NOT_A_REAL_API_KEY_W4',1000,900,200,
      'active','2027-12-31');
    DECLARE @a INT=SCOPE_IDENTITY();
    INSERT dbo.Inventory(account_id,current_quota) VALUES(@a,100);
    INSERT dbo.InventoryLog(account_id,change_type,change_amount,reason)
    VALUES(@a,'purchase',1000,N'W4边界期初'),(@a,'consumption',-900,N'W4边界消耗');
    IF NOT EXISTS(SELECT 1 FROM dbo.v_InventoryStatus WHERE account_id=@a AND stock_state='low')
        THROW 51341,N'Low quota account missing',1;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
IF @@TRANCOUNT<>0 THROW 51342,N'Open transaction after boundary tests',1;
PRINT N'PASS VFY11 boundary positives';
PRINT N'PASS v0.1 verification';
GO
