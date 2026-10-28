USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
PRINT N'Q01 - multi-table order detail query';
SELECT TOP (8)
    o.order_id,u.username,o.status,
    d.detail_id,p.product_id,p.model_provider,p.token_amount,
    d.quantity,d.subtotal,d.total_tokens
FROM dbo.Orders o
JOIN dbo.Users u ON u.user_id=o.user_id
JOIN dbo.OrderDetails d ON d.order_id=o.order_id
JOIN dbo.Products p ON p.product_id=d.product_id
ORDER BY o.order_id,d.detail_id;

SELECT COUNT(*) AS q01_total_rows
FROM dbo.Orders o
JOIN dbo.Users u ON u.user_id=o.user_id
JOIN dbo.OrderDetails d ON d.order_id=o.order_id
JOIN dbo.Products p ON p.product_id=d.product_id;

IF (SELECT COUNT(*) FROM dbo.v_OrderDetail)<>184 THROW 51461,N'Join count mismatch',1;
PRINT N'PASS verified evidence result';
