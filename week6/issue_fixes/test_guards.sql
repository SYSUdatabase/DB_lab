-- Week 5 issues: v1.1 isolated negative/positive checks. Roll back every test.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014' THROW 51940,'Wrong isolated test database',1;
DECLARE @got INT,@oid INT;
-- I01: pending order may be drafted, cannot be paid without details.
SET @got=0;
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.Orders(user_id,total_amount,total_tokens,status)
 VALUES(1,0,0,'pending');
 SET @oid=SCOPE_IDENTITY();
 UPDATE dbo.Orders SET status='paid', paid_at=SYSDATETIME() WHERE order_id=@oid;
 ROLLBACK;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK;
END CATCH;
IF @got<>51920 THROW 51941,'I01 empty paid order not blocked',1;
PRINT 'PASS I01 pending to paid without details rejected';
-- I01/I06: complete order can transition to paid, one row cost sums.
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.Orders(user_id,total_amount,total_tokens,status)
 VALUES(1,1.00,10,'pending');
 SET @oid=SCOPE_IDENTITY();
 INSERT dbo.OrderDetails(order_id,product_id,quantity,unit_price,subtotal,tokens_per_unit,total_tokens)
 VALUES (@oid,1,1,1.00,1.00,10,10);
 UPDATE dbo.Orders SET status='paid',paid_at=SYSDATETIME() WHERE order_id=@oid;
 IF NOT EXISTS (SELECT 1 FROM dbo.Orders WHERE order_id=@oid AND status='paid')
  THROW 51942,'Complete order did not finalize',1;
 ROLLBACK;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
PRINT 'PASS I01/I06 complete matched order finalized and rolled back';
-- I01/I06: paid detail records cannot be edited directly.
SET @got=0;
BEGIN TRY
 BEGIN TRAN;
 UPDATE dbo.OrderDetails SET quantity=quantity
 WHERE detail_id=(SELECT TOP(1) d.detail_id FROM dbo.OrderDetails d
 JOIN dbo.Orders o ON o.order_id=d.order_id WHERE o.status='paid' ORDER BY d.detail_id);
 ROLLBACK;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK;
END CATCH;
IF @got<>51921 THROW 51943,'Finalized details editable',1;
PRINT 'PASS I01/I06 paid detail immutable';
-- I05: invalid registration/lifecycle on new usage blocked.
SET @got=0;
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.TokenUsageLogs(user_id,product_id,account_id,tokens_used,upstream_tokens_consumed,used_at)
 VALUES (1,1,1,1,1,'1900-01-01');
 ROLLBACK;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK;
END CATCH;
IF @got<>51922 THROW 51944,'Invalid usage lifecycle not blocked',1;
PRINT 'PASS I05 pre-registration usage rejected';
-- I08 invalid typed inventory event reference.
SET @got=0;
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.InventoryLog(account_id,change_type,change_amount,reference_type,reference_id)
 VALUES (1,'adjustment',1,'restock_task',-1);
 ROLLBACK;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK;
END CATCH;
IF @got<>51923 THROW 51945,'Inventory log dangling typed reference accepted',1;
PRINT 'PASS I08 restock_task reference rejected';
-- I08 invalid polymorphic exception reference.
SET @got=0;
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.ExceptionLog(exception_type,related_table,related_id,error_message)
 VALUES ('system_error','Orders',-1,N'Test invalid reference');
 ROLLBACK;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK;
END CATCH;
IF @got<>51924 THROW 51946,'Exception dangling typed reference accepted',1;
PRINT 'PASS I08 exception reference rejected';
IF @@TRANCOUNT<>0 THROW 51947,'Open transaction after tests',1;
PRINT 'PASS V11 GUARD REGRESSION';