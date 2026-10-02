SET NOCOUNT ON;
PRINT N'Core statistical views';
SELECT N'v_OrderDetail' AS view_name,COUNT(*) AS rows FROM dbo.v_OrderDetail
UNION ALL SELECT N'v_ProductSales',COUNT(*) FROM dbo.v_ProductSales
UNION ALL SELECT N'v_MemberSpending',COUNT(*) FROM dbo.v_MemberSpending
UNION ALL SELECT N'v_InventoryStatus',COUNT(*) FROM dbo.v_InventoryStatus;

SELECT SUM(revenue) AS paid_revenue,SUM(units_sold) AS package_units,
       SUM(tokens_sold) AS paid_tokens
FROM dbo.v_ProductSales;

SELECT TOP(4) product_id,model_provider,units_sold,revenue,tokens_sold
FROM dbo.v_ProductSales ORDER BY revenue DESC,product_id;

SELECT account_id,provider,current_quota,safety_threshold,stock_state
FROM dbo.v_InventoryStatus ORDER BY account_id;
