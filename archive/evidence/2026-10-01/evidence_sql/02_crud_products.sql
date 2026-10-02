SET NOCOUNT ON;
BEGIN TRANSACTION;
PRINT N'Before insert';
SELECT COUNT(*) AS demo_rows FROM dbo.Products WHERE name=N'W4_SCREENSHOT_PRODUCT';
INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status)
VALUES(N'W4_SCREENSHOT_PRODUCT',N'CRUD screenshot evidence',9.90,'Other',920001,920001,'active');
DECLARE @id INT=SCOPE_IDENTITY();
PRINT N'After INSERT';
SELECT product_id,name,price,status FROM dbo.Products WHERE product_id=@id;
UPDATE dbo.Products SET price=12.90,status='inactive' WHERE product_id=@id;
PRINT N'After UPDATE';
SELECT product_id,name,price,status FROM dbo.Products WHERE product_id=@id;
DELETE dbo.Products WHERE product_id=@id;
PRINT N'After DELETE';
SELECT COUNT(*) AS demo_rows FROM dbo.Products WHERE product_id=@id;
ROLLBACK TRANSACTION;
PRINT N'PASS Products CRUD; transaction rolled back';
