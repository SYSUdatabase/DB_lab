USE [$(DatabaseName)];
GO
SET XACT_ABORT ON;
SET NOCOUNT ON;
BEGIN TRANSACTION;
INSERT dbo.Orders(user_id,total_amount,total_tokens,status,created_at)
VALUES(1,6.90,100000,'pending','2026-09-30 10:00:00');
DECLARE @o INT=SCOPE_IDENTITY();
INSERT dbo.OrderDetails(order_id,product_id,quantity,unit_price,subtotal,tokens_per_unit,total_tokens)
VALUES(@o,2,1,6.90,6.90,100000,100000);
IF NOT EXISTS(SELECT 1 FROM dbo.OrderDetails WHERE order_id=@o AND subtotal=6.90) THROW 51457,N'Order insert failed',1;
PRINT N'After INSERT';
SELECT o.order_id,o.status,d.product_id,d.quantity,d.subtotal
FROM dbo.Orders o JOIN dbo.OrderDetails d ON d.order_id=o.order_id
WHERE o.order_id=@o;
UPDATE dbo.Orders SET status='cancelled' WHERE order_id=@o;
IF NOT EXISTS(SELECT 1 FROM dbo.Orders WHERE order_id=@o AND status='cancelled') THROW 51458,N'Order update failed',1;
PRINT N'After UPDATE';
SELECT order_id,status,total_amount,total_tokens FROM dbo.Orders WHERE order_id=@o;
DELETE dbo.OrderDetails WHERE order_id=@o;
DELETE dbo.Orders WHERE order_id=@o;
PRINT N'After DELETE';
SELECT COUNT(*) AS demo_rows FROM dbo.Orders WHERE order_id=@o;
IF EXISTS(SELECT 1 FROM dbo.Orders WHERE order_id=@o) OR EXISTS(SELECT 1 FROM dbo.OrderDetails WHERE order_id=@o) THROW 51452,N'Order delete failed',1;
ROLLBACK TRANSACTION;
PRINT N'PASS Orders CRUD; transaction rolled back';
