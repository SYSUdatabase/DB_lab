SET NOCOUNT ON;
PRINT N'Q02 - paid product sales (top 5)';
SELECT TOP (5) product_id,model_provider,units_sold,revenue,tokens_sold
FROM dbo.v_ProductSales ORDER BY revenue DESC,product_id;
SELECT SUM(units_sold) AS units_sold,SUM(revenue) AS revenue
FROM dbo.v_ProductSales;

PRINT N'Q05 - users without paid orders';
SELECT user_id,username
FROM dbo.v_MemberSpending
WHERE paid_orders=0
ORDER BY user_id;
SELECT COUNT(*) AS users_without_paid_orders
FROM dbo.v_MemberSpending WHERE paid_orders=0;
