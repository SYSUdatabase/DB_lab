-- 第12周模拟补货入库事务。由 install.sql 安装；验证见 test_transactions.sql。
--
-- 补货单为 dbo.RestockTask：员工在页面上为某个上游账号填写计划补货量（target_amount），
-- 入库时再填写实际到货量（actual_amount）。补货单编号、账号（对应供应商的商品）和数量
-- 的对应关系保存在这张表里，第四阶段可把人工填写的数量换成预测结果。
-- 一张补货单只能入库一次：状态条件更新 WHERE status IN ('pending','in_progress')
-- 并检查受影响行数；已入库的单据返回 53311，不会第二次增加库存。
--
-- 事务边界与调用关系：
--   Web  app.[Execute] 'restocks.complete' （外层事务，入口统一提交或回滚）
--     └─ dbo.usp_W6_RestockAccount         （保留原名的薄封装）
--          └─ w12.usp_ReceiveRestock        （本过程：增加额度与库存、写流水、完成单据）
--               └─ UPDATE dbo.Inventory 触发 dbo.trg_W11_InventoryAudit，审计记录随事务一起提交或回滚。
-- 测试时可用会话上下文 w12.fail_point='restock_after_inventory'，在库存已增加、
-- 单据未完成之前主动抛错，验证回滚。
CREATE OR ALTER PROCEDURE w12.usp_ReceiveRestock
 @task_id INT,
 @actual_amount BIGINT,
 @emit_result BIT=1,
 @app_result_id INT=NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'$(DatabaseName)'
  THROW 53302,'Wrong database for restocking',1;
 IF @actual_amount IS NULL OR @actual_amount<=0
  THROW 53303,'Restock amount must be positive',1;
 DECLARE @now DATETIME2(0)=CONVERT(DATETIME2(0),SYSDATETIME()),
         @account_id INT,@operator INT,@task_status VARCHAR(20),@quota BIGINT,@remaining BIGINT,
         @provider VARCHAR(50);
 BEGIN TRY
  SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  BEGIN TRANSACTION;
  SELECT @account_id=t.account_id,@operator=t.assigned_to,@task_status=t.status
  FROM dbo.RestockTask t WITH(UPDLOCK,HOLDLOCK) WHERE t.task_id=@task_id;
  IF @task_status IS NULL
   THROW 53310,'Restock task does not exist',1;
  IF @task_status='completed'
   THROW 53311,'Restock task was already received; inventory is not added again',1;
  IF @task_status NOT IN ('pending','in_progress')
   THROW 53312,'Restock task is closed and cannot be received',1;
  -- 定位供应商时不把共享锁带入入口锁等待；取得入口锁后按该供应商重新核对账号。
  SELECT @provider=provider FROM dbo.UpstreamAccount WITH(READCOMMITTEDLOCK)
  WHERE account_id=@account_id;
  IF @provider IS NULL THROW 53305,'No restockable upstream account/inventory pair',1;
  EXEC w12.usp_LockInventoryProvider @provider;
  SELECT @quota=a.total_quota,@remaining=i.current_quota
  FROM dbo.UpstreamAccount a WITH(UPDLOCK,HOLDLOCK)
  JOIN dbo.Inventory i WITH(UPDLOCK,HOLDLOCK) ON i.account_id=a.account_id
  WHERE a.account_id=@account_id AND a.provider=@provider
    AND a.status IN ('active','depleted','suspended');
  IF @quota IS NULL OR @remaining IS NULL
   THROW 53305,'No restockable upstream account/inventory pair',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Products p JOIN dbo.UpstreamAccount a ON a.provider=p.model_provider
     WHERE a.account_id=@account_id)
   THROW 53313,'No product is sold from this upstream account provider',1;
  IF @actual_amount>9223372036854775807-@quota
     OR @actual_amount>9223372036854775807-@remaining
   THROW 53306,'Restock would overflow quota or inventory',1;
  IF @remaining<>(SELECT a.total_quota-a.used_quota FROM dbo.UpstreamAccount a
                   WHERE a.account_id=@account_id)
   THROW 53307,'Pre-existing quota/inventory divergence',1;
  -- A successful purchase restores an exhausted, still-valid upstream account only.
  -- Do not override manual suspension or reactivate an expired account.
  UPDATE dbo.UpstreamAccount SET total_quota=total_quota+@actual_amount,
    status=CASE WHEN status='depleted' AND created_at<=SYSDATETIME()
       AND (expires_at IS NULL OR expires_at>SYSDATETIME())
       THEN 'active' ELSE status END,updated_at=@now
  WHERE account_id=@account_id;
  UPDATE dbo.Inventory SET current_quota=current_quota+@actual_amount,last_updated_at=@now
  WHERE account_id=@account_id;
  INSERT dbo.InventoryLog(account_id,change_type,change_amount,
    reference_type,reference_id,reason,operator_id,created_at)
  VALUES(@account_id,'restock',@actual_amount,'restock_task',@task_id,
        N'Completed approved restock',@operator,@now);
  IF CONVERT(NVARCHAR(40),SESSION_CONTEXT(N'w12.fail_point'))=N'restock_after_inventory'
   THROW 54491,'Injected failure after adding inventory and before completing the restock task',1;
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
  SET @app_result_id=@task_id;
  IF @emit_result=1 SELECT @task_id AS task_id,@account_id AS account_id,
         @actual_amount AS added_quota,'completed' AS status,@now AS completed_at;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  THROW;
 END CATCH;
END;
GO
-- 原补货完成过程改为调用新事务，Web 的“完成补货”与 SQL 直接调用走同一实现。
CREATE OR ALTER PROCEDURE dbo.usp_W6_RestockAccount
 @task_id INT,
 @actual_amount BIGINT,
 @emit_result BIT=1,
 @app_result_id INT=NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 EXEC w12.usp_ReceiveRestock @task_id,@actual_amount,@emit_result=@emit_result,@app_result_id=@app_result_id OUTPUT;
END;
GO
