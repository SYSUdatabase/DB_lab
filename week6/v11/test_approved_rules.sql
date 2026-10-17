-- Approved I02/I03/I04/I07 functional regression; all writes rolled back.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
 THROW 52160,'Only v1.1 isolated database allowed',1;
DECLARE @got INT=0,@order_id INT,@account_id INT,@task_id INT;
-- I02/I03: registered pending order; same product merged by quantity.
BEGIN TRY
 BEGIN TRANSACTION;
 CREATE TABLE #w5_order_ids(order_id INT NOT NULL);
 INSERT #w5_order_ids EXEC dbo.usp_W5_CreateRegisteredOrder @user_id=1;
 SELECT @order_id=order_id FROM #w5_order_ids;
 IF @order_id IS NULL THROW 52161,'Order id missing',1;
 EXEC dbo.usp_W5_AddMergedOrderItem @order_id=@order_id,@product_id=1,@quantity=2;
 EXEC dbo.usp_W5_AddMergedOrderItem @order_id=@order_id,@product_id=1,@quantity=3;
 IF (SELECT COUNT(*) FROM dbo.OrderDetails WHERE order_id=@order_id AND product_id=1)<>1
  OR (SELECT quantity FROM dbo.OrderDetails WHERE order_id=@order_id AND product_id=1)<>5
  OR EXISTS(
   SELECT 1 FROM dbo.Orders o
   JOIN dbo.OrderDetails d ON d.order_id=o.order_id
   WHERE o.order_id=@order_id AND (o.total_amount<>d.subtotal OR o.total_tokens<>d.total_tokens)
  ) THROW 52162,'Merged line or summary incorrect',1;
 -- I02: trying to insert the same order/product as a second row must fail UNIQUE.
 SET @got=0;
 BEGIN TRY
  INSERT dbo.OrderDetails(order_id,product_id,quantity,unit_price,subtotal,tokens_per_unit,total_tokens)
  SELECT order_id,product_id,1,unit_price,unit_price,tokens_per_unit,
         CONVERT(BIGINT,tokens_per_unit)
  FROM dbo.OrderDetails WHERE order_id=@order_id AND product_id=1;
 END TRY
 BEGIN CATCH
  SET @got=ERROR_NUMBER();
 END CATCH;
 IF @got NOT IN (2627,2601) THROW 52174,'Duplicate order/product not rejected by UNIQUE',1;
 UPDATE dbo.Orders SET status='paid',paid_at=SYSDATETIME() WHERE order_id=@order_id;
 IF NOT EXISTS(SELECT 1 FROM dbo.Orders WHERE order_id=@order_id AND status='paid')
  THROW 52163,'Merged order could not be paid',1;
 DROP TABLE #w5_order_ids;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
PRINT 'PASS I02 quantity merged; I03 registered paid order; rolled back';
-- I03: nonexistent user cannot start an order, even with direct DML.
SET @got=0;
BEGIN TRY
 EXEC dbo.usp_W5_CreateRegisteredOrder @user_id=-999999;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
END CATCH;
IF @got<>52123 THROW 52164,'Unregistered order procedure was not rejected',1;
SET @got=0;
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.Orders(user_id,total_amount,total_tokens,status)
 VALUES(-999999,0,0,'pending');
 ROLLBACK;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK;
END CATCH;
IF @got<>547 THROW 52165,'FK did not block orphan guest order',1;
PRINT 'PASS I03 direct and procedure unregistered order blocked';
-- I04: multi-column quota snapshot created with parent, no row leak.
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,used_quota,
    safety_threshold,status)
 VALUES('Other',N'__w5_i04_rollback_probe__',N'NON_CREDENTIAL_TEST_PLACEHOLDER',
    100,3,2,'active');
 SET @account_id=CONVERT(INT,SCOPE_IDENTITY());
 IF (SELECT COUNT(*) FROM dbo.Inventory WHERE account_id=@account_id)<>1
  OR (SELECT current_quota FROM dbo.Inventory WHERE account_id=@account_id)<>97
  THROW 52166,'New account did not get exact-one matching inventory',1;
 ROLLBACK;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
PRINT 'PASS I04 new account automatically gets one matching Inventory (rollback)';
-- I04: orphan inventory deletion fails.
SET @got=0;
BEGIN TRY
 BEGIN TRANSACTION;
 DELETE dbo.Inventory WHERE account_id=1;
 ROLLBACK;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK;
END CATCH;
IF @got<>52108 THROW 52167,'Inventory detached from account',1;
PRINT 'PASS I04 orphan inventory deletion rejected';
-- I07: system task with NULL employee is valid, manual with employee valid.
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.RestockTask(account_id,trigger_reason,restock_method,
    target_amount,created_by,created_source,status)
 VALUES(1,'scheduled','api_recharge',1000,NULL,'system','pending');
 SET @task_id=CONVERT(INT,SCOPE_IDENTITY());
 IF NOT EXISTS(SELECT 1 FROM dbo.RestockTask WHERE task_id=@task_id
    AND created_by IS NULL AND created_source='system')
  THROW 52168,'System creator missing',1;
 INSERT dbo.RestockTask(account_id,trigger_reason,restock_method,
    target_amount,created_by,status)
 VALUES(1,'manual','manual_purchase',1000,1,'pending');
 IF NOT EXISTS(SELECT 1 FROM dbo.RestockTask
   WHERE task_id=CONVERT(INT,SCOPE_IDENTITY()) AND created_by=1 AND created_source='manual')
  THROW 52169,'Manual creator default missing',1;
 ROLLBACK;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
PRINT 'PASS I07 system NULL/manual employee defaults (rolled back)';
-- I07: manual NULL and system employee both violate CHECK.
SET @got=0;
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.RestockTask(account_id,trigger_reason,restock_method,
  target_amount,created_by,created_source)
 VALUES(1,'scheduled','api_recharge',1000,NULL,'manual');
 ROLLBACK;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER(); IF XACT_STATE()<>0 ROLLBACK;
END CATCH;
IF @got<>547 THROW 52170,'Manual NULL creator should be rejected by CHECK',1;
SET @got=0;
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.RestockTask(account_id,trigger_reason,restock_method,
  target_amount,created_by,created_source)
 VALUES(1,'scheduled','api_recharge',1000,1,'system');
 ROLLBACK;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER(); IF XACT_STATE()<>0 ROLLBACK;
END CATCH;
IF @got<>547 THROW 52171,'System task with employee should be rejected by CHECK',1;
IF @@TRANCOUNT<>0 THROW 52172,'Test leaked a transaction',1;
IF EXISTS(SELECT 1 FROM sys.check_constraints
 WHERE name='CK_RestockTask_creator_source' AND (is_disabled=1 OR is_not_trusted=1))
 THROW 52173,'Creator CHECK not trusted',1;
PRINT 'PASS I07 manual/system creator CHECK negative tests';
PRINT 'PASS I02 I03 I04 I07 APPROVED RULES REGRESSION';