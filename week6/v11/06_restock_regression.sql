-- Isolated v1.1 managed restock tests; no persistent test rows.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
 THROW 53400,'Wrong isolated test database',1;
IF OBJECT_ID('dbo.usp_W6_RestockAccount','P') IS NULL
 THROW 53401,'Restock procedure not installed',1;
DECLARE @task_id INT=(
 SELECT TOP(1) task_id FROM dbo.RestockTask
 WHERE status IN ('pending','in_progress') ORDER BY task_id
),@acct INT=(SELECT account_id FROM dbo.RestockTask WHERE task_id=(
 SELECT TOP(1) task_id FROM dbo.RestockTask
 WHERE status IN ('pending','in_progress') ORDER BY task_id
)),@original_total BIGINT,@original_inventory BIGINT,@original_logs BIGINT;
IF @task_id IS NULL THROW 53402,'No pending restock in sample',1;
SELECT @original_total=total_quota FROM dbo.UpstreamAccount WHERE account_id=@acct;
SELECT @original_inventory=current_quota FROM dbo.Inventory WHERE account_id=@acct;
SELECT @original_logs=COUNT_BIG(*) FROM dbo.InventoryLog;
BEGIN TRY
 BEGIN TRANSACTION;
 EXECUTE AS USER='hub_manager_demo';
 EXEC dbo.usp_W6_RestockAccount @task_id=@task_id,@actual_amount=5000;
 REVERT;
 IF (SELECT total_quota FROM dbo.UpstreamAccount WHERE account_id=@acct)
    <>@original_total+5000
 OR (SELECT current_quota FROM dbo.Inventory WHERE account_id=@acct)
    <>@original_inventory+5000
 OR (SELECT status FROM dbo.RestockTask WHERE task_id=@task_id)<>'completed'
 OR (SELECT COUNT_BIG(*) FROM dbo.InventoryLog)<>@original_logs+1
 OR NOT EXISTS(SELECT 1 FROM dbo.InventoryLog
    WHERE reference_type='restock_task' AND reference_id=@task_id
      AND change_amount=5000 AND account_id=@acct)
 THROW 53403,'Restock must adjust task, account, inventory and audit atomically',1;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 IF USER_NAME()<>'dbo' REVERT;
 THROW;
END CATCH;
IF (SELECT total_quota FROM dbo.UpstreamAccount WHERE account_id=@acct)<>@original_total
 OR (SELECT current_quota FROM dbo.Inventory WHERE account_id=@acct)<>@original_inventory
 OR (SELECT COUNT_BIG(*) FROM dbo.InventoryLog)<>@original_logs
 THROW 53404,'Restock rollback changed persisted values',1;
PRINT 'PASS Y01 managed restock atomic state, quota and audit; rollback';
GO
DECLARE @err INT=0,@id INT=(SELECT TOP(1) task_id FROM dbo.RestockTask
 WHERE status IN ('pending','in_progress') ORDER BY task_id);
BEGIN TRY
 EXEC dbo.usp_W6_RestockAccount @task_id=@id,@actual_amount=0;
END TRY
BEGIN CATCH SET @err=ERROR_NUMBER(); END CATCH;
IF @err<>53303 THROW 53405,'Zero restock amount accepted',1;
PRINT 'PASS Y02 zero restock rejected';
GO
DECLARE @err INT=0,@id INT=(SELECT TOP(1) task_id FROM dbo.RestockTask
 WHERE status='completed' ORDER BY task_id);
BEGIN TRY
 EXEC dbo.usp_W6_RestockAccount @task_id=@id,@actual_amount=1000;
END TRY
BEGIN CATCH SET @err=ERROR_NUMBER(); END CATCH;
IF @err<>53304 THROW 53406,'Already completed task was paid again',1;
PRINT 'PASS Y03 double-restock rejected';
GO
DECLARE @err INT=0;
BEGIN TRY
 BEGIN TRANSACTION;
 EXECUTE AS USER='hub_manager_demo';
 UPDATE dbo.Inventory SET current_quota=current_quota+1 WHERE account_id=1;
 REVERT;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 SET @err=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 IF USER_NAME()<>'dbo' REVERT;
END CATCH;
IF @err<>53116 THROW 53407,'Manager direct inventory change not blocked',1;
PRINT 'PASS Y04 direct inventory updates rejected';
GO
IF @@TRANCOUNT<>0 OR USER_NAME()<>'dbo'
 THROW 53408,'Test left open transaction or execution context',1;
PRINT 'PASS V1.1 CONTROLLED RESTOCK TESTS Y01-Y04';
GO
