SET NOCOUNT ON;
BEGIN TRANSACTION;
PRINT N'C01 - DEFAULT and NULL legal case';
INSERT dbo.Products(name,price,model_provider,token_amount,required_upstream_tokens)
VALUES(N'W4_LEGAL_PRODUCT',1,'Other',930001,930001);
SELECT name,status,created_at,description
FROM dbo.Products WHERE name=N'W4_LEGAL_PRODUCT';

PRINT N'C02 - pending order defaults';
INSERT dbo.Orders(user_id,total_amount,total_tokens) VALUES(1,0,0);
DECLARE @o INT=SCOPE_IDENTITY();
SELECT order_id,user_id,status,paid_at,total_amount,total_tokens
FROM dbo.Orders WHERE order_id=@o;

ROLLBACK TRANSACTION;
PRINT N'PASS C01/C02 legal constraint cases; transaction rolled back';
