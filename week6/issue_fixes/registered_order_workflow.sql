-- I02/I03 approved procedures, sandbox v1.1 only.
:on error exit
SET NOCOUNT ON;
IF DB_NAME()<>N'TokenHubDB_v11_Issues_20261014'
 THROW 52120,'Refuse wrong database',1;
IF OBJECT_ID(N'dbo.usp_W5_CreateRegisteredOrder',N'P') IS NOT NULL
 OR OBJECT_ID(N'dbo.usp_W5_AddMergedOrderItem',N'P') IS NOT NULL
 THROW 52121,'Approved procedures already exist',1;
GO
CREATE PROCEDURE dbo.usp_W5_CreateRegisteredOrder
 @user_id INT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
  THROW 52122,'Wrong database',1;
 IF @user_id IS NULL OR NOT EXISTS(
   SELECT 1 FROM dbo.Users WHERE user_id=@user_id AND status='active')
  THROW 52123,'Existing active Users record required before order',1;
 DECLARE @id INT;
 BEGIN TRY
  BEGIN TRAN;
  INSERT dbo.Orders(user_id,total_amount,total_tokens,status)
  VALUES(@user_id,0,0,'pending');
  SET @id=CONVERT(INT,SCOPE_IDENTITY());
  COMMIT TRAN;
  SELECT @id AS order_id;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  THROW;
 END CATCH;
END;
GO
CREATE PROCEDURE dbo.usp_W5_AddMergedOrderItem
 @order_id INT,
 @product_id INT,
 @quantity INT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
  THROW 52124,'Wrong database',1;
 IF @quantity IS NULL OR @quantity<=0
  THROW 52125,'Quantity must be positive',1;
 DECLARE @price DECIMAL(10,2),@token_amount INT,
     @oldqty INT,@unitprice DECIMAL(10,2),@oldtoken INT;
 BEGIN TRY
  SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  BEGIN TRAN;
  IF NOT EXISTS(SELECT 1 FROM dbo.Orders WITH(UPDLOCK,HOLDLOCK)
      WHERE order_id=@order_id AND status='pending')
   THROW 52126,'Order must be an existing pending draft',1;
  SELECT @price=price,@token_amount=token_amount
  FROM dbo.Products WITH(UPDLOCK,HOLDLOCK)
  WHERE product_id=@product_id AND status='active';
  IF @price IS NULL OR @token_amount IS NULL
   THROW 52127,'Product missing or inactive',1;
  SELECT @oldqty=quantity,@unitprice=unit_price,@oldtoken=tokens_per_unit
  FROM dbo.OrderDetails WITH(UPDLOCK,HOLDLOCK)
  WHERE order_id=@order_id AND product_id=@product_id;
  IF @oldqty IS NOT NULL
  BEGIN
   IF @oldqty>2147483647-@quantity
    THROW 52128,'Quantity overflow',1;
   -- Retain the first recorded purchase price/token snapshot.
   UPDATE dbo.OrderDetails SET quantity=@oldqty+@quantity,
      subtotal=CONVERT(DECIMAL(10,2),CONVERT(DECIMAL(18,2),@oldqty+@quantity)*@unitprice),
      total_tokens=CONVERT(BIGINT,@oldqty+@quantity)*@oldtoken
   WHERE order_id=@order_id AND product_id=@product_id;
  END
  ELSE
  BEGIN
   INSERT dbo.OrderDetails(order_id,product_id,quantity,unit_price,
      subtotal,tokens_per_unit,total_tokens)
   VALUES(@order_id,@product_id,@quantity,@price,
      CONVERT(DECIMAL(10,2),CONVERT(DECIMAL(18,2),@quantity)*@price),
      @token_amount,CONVERT(BIGINT,@quantity)*@token_amount);
  END;
  UPDATE o SET total_amount=x.amount,total_tokens=x.tokens
  FROM dbo.Orders o CROSS APPLY (
   SELECT SUM(d.subtotal) amount,SUM(d.total_tokens) tokens
   FROM dbo.OrderDetails d WHERE d.order_id=@order_id
  ) x
  WHERE o.order_id=@order_id;
  IF @@ROWCOUNT<>1 THROW 52129,'Header not updated',1;
  COMMIT TRAN;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  SELECT detail_id,order_id,product_id,quantity,subtotal,total_tokens
  FROM dbo.OrderDetails WHERE order_id=@order_id AND product_id=@product_id;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  THROW;
 END CATCH;
END;
GO
GRANT EXECUTE ON dbo.usp_W5_CreateRegisteredOrder TO hub_manager;
GRANT EXECUTE ON dbo.usp_W5_AddMergedOrderItem TO hub_manager;
PRINT 'PASS registered order and merged item procedures created';
GO