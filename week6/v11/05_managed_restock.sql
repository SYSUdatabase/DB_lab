-- v1.1: quota increase must atomically update account, Inventory,
-- InventoryLog and the originating RestockTask. No arbitrary direct quota write.
:on error exit
SET NOCOUNT ON;
IF DB_NAME()<>N'TokenHubDB_v11_Issues_20261014'
 THROW 53300,'Wrong isolated v1.1 target',1;
IF OBJECT_ID('dbo.usp_W6_RestockAccount','P') IS NOT NULL
 OR OBJECT_ID('dbo.trg_W6_InventoryLogWrite','TR') IS NULL
 THROW 53301,'Controlled write hardening missing or restock procedure already exists',1;
GO
CREATE PROCEDURE dbo.usp_W6_RestockAccount
 @task_id INT,
 @actual_amount BIGINT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
  THROW 53302,'Wrong database for restocking',1;
 IF @actual_amount IS NULL OR @actual_amount<=0
  THROW 53303,'Restock amount must be positive',1;
 DECLARE @now DATETIME2(0)=CONVERT(DATETIME2(0),SYSDATETIME()),
         @account_id INT,@operator INT,@quota BIGINT,@remaining BIGINT;
 BEGIN TRY
  SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  BEGIN TRANSACTION;
  SELECT @account_id=t.account_id,@operator=t.assigned_to
  FROM dbo.RestockTask t WITH(UPDLOCK,HOLDLOCK)
  WHERE t.task_id=@task_id AND t.status IN ('pending','in_progress');
  IF @account_id IS NULL
   THROW 53304,'Missing, finalized or already completed restock task',1;
  SELECT @quota=a.total_quota,@remaining=i.current_quota
  FROM dbo.UpstreamAccount a WITH(UPDLOCK,HOLDLOCK)
  JOIN dbo.Inventory i WITH(UPDLOCK,HOLDLOCK) ON i.account_id=a.account_id
  WHERE a.account_id=@account_id
    AND a.status IN ('active','depleted','suspended');
  IF @quota IS NULL OR @remaining IS NULL
   THROW 53305,'No restockable upstream account/inventory pair',1;
  IF @actual_amount>9223372036854775807-@quota
     OR @actual_amount>9223372036854775807-@remaining
   THROW 53306,'Restock would overflow quota or inventory',1;
  IF @remaining<>(SELECT a.total_quota-a.used_quota FROM dbo.UpstreamAccount a
                   WHERE a.account_id=@account_id)
   THROW 53307,'Pre-existing quota/inventory divergence',1;
  UPDATE dbo.UpstreamAccount SET total_quota=total_quota+@actual_amount,updated_at=@now
  WHERE account_id=@account_id;
  UPDATE dbo.Inventory SET current_quota=current_quota+@actual_amount,last_updated_at=@now
  WHERE account_id=@account_id;
  INSERT dbo.InventoryLog(account_id,change_type,change_amount,
    reference_type,reference_id,reason,operator_id,created_at)
  VALUES(@account_id,'restock',@actual_amount,'restock_task',@task_id,
        N'Completed approved restock',@operator,@now);
  UPDATE dbo.RestockTask SET status='completed',actual_amount=@actual_amount,
          completed_at=@now WHERE task_id=@task_id AND status IN ('pending','in_progress');
  IF @@ROWCOUNT<>1
   THROW 53308,'Task was finalized concurrently',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.UpstreamAccount a JOIN dbo.Inventory i
     ON i.account_id=a.account_id WHERE a.account_id=@account_id
       AND i.current_quota=a.total_quota-a.used_quota)
   THROW 53309,'Restock violated quota/inventory balance',1;
  COMMIT TRANSACTION;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  SELECT @task_id AS task_id,@account_id AS account_id,
         @actual_amount AS added_quota,@now AS completed_at;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  THROW;
 END CATCH;
END;
GO
GRANT EXECUTE ON dbo.usp_W6_RestockAccount TO hub_manager;
PRINT 'PASS managed restock transaction installed';
GO
