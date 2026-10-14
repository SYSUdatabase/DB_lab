-- Isolated v1.1 additional guard tests, no persistent rows.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014' THROW 51990,'Wrong target',1;
DECLARE @actor SYSNAME=USER_NAME(),@got INT=0,@oid INT;
-- Manager direct insert into event ledger must be rejected.
BEGIN TRY
 BEGIN TRANSACTION;
 EXECUTE AS USER='hub_manager_demo';
 INSERT dbo.TokenUsageLogs(user_id,product_id,account_id,tokens_used,upstream_tokens_consumed,used_at)
 VALUES(1,1,1,1,1,CONVERT(DATETIME2(0),SYSDATETIME()));
 REVERT;
 ROLLBACK;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK;
 IF USER_NAME()<>@actor REVERT;
END CATCH;
IF @got<>51982 THROW 51991,'Manager direct insert was not guarded',1;
IF USER_NAME()<>@actor OR @@TRANCOUNT<>0 THROW 51992,'Failed restore execution context',1;
PRINT 'PASS manager direct event insert rejected; proc required';
-- DELETE an order with a typed exception reference.
SET @got=0;
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.Orders(user_id,total_amount,total_tokens,status)
 VALUES(1,0,0,'pending');
 SET @oid=CONVERT(INT,SCOPE_IDENTITY());
 INSERT dbo.ExceptionLog(exception_type,related_table,related_id,error_message)
 VALUES('system_error','Orders',@oid,N'v1.1 guard audit test');
 DELETE FROM dbo.Orders WHERE order_id=@oid;
 ROLLBACK;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK;
END CATCH;
IF @got<>51983 THROW 51993,'Deleted an order still referenced by exception',1;
PRINT 'PASS referenced order deletion rejected';
-- DELETE existing RestockTask that is referenced by InventoryLog.
SET @got=0;
BEGIN TRY
 BEGIN TRANSACTION;
 DELETE dbo.RestockTask WHERE task_id=(
  SELECT TOP(1) t.task_id FROM dbo.RestockTask t
    JOIN dbo.InventoryLog l ON l.reference_type='restock_task' AND l.reference_id=t.task_id
    ORDER BY t.task_id
 );
 ROLLBACK;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK;
END CATCH;
IF @got<>51985 THROW 51994,'Deleted referenced restock task',1;
PRINT 'PASS referenced restock deletion rejected';
IF @@TRANCOUNT<>0 OR USER_NAME()<>@actor THROW 51995,'Leaked transaction or impersonation',1;
PRINT 'PASS V11 REFERENCE AND ROLE HARDENING';