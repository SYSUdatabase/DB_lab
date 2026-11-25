-- RED/GREEN: both production paths must take the same transaction-owned provider lock.
SET NOCOUNT ON;
DECLARE @order int,@task int,@observed nvarchar(32);
SELECT @order=order_a,@task=task_id FROM w13lab.Business;
BEGIN TRY
 BEGIN TRAN;
 EXEC w12.usp_CompleteOrder @order,0;
 SET @observed=APPLOCK_MODE('public','TokenHub.Inventory.Other','Transaction');
 IF @observed<>'Exclusive' THROW 57114,'Order did not hold the shared provider lock',1;
 ROLLBACK;
 BEGIN TRAN;
 EXEC w12.usp_ReceiveRestock @task,5,0;
 SET @observed=APPLOCK_MODE('public','TokenHub.Inventory.Other','Transaction');
 IF @observed<>'Exclusive' THROW 57115,'Restock did not hold the shared provider lock',1;
 ROLLBACK;
 SELECT @observed AS common_lock_mode,@@TRANCOUNT AS trancount;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
