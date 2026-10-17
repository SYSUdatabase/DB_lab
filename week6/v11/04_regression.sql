-- v1.1 extension integration tests: all test writes rolled back.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
 THROW 53200,'Wrong isolated test database',1;
IF OBJECT_ID('dbo.usp_W6_PayPendingOrder','P') IS NULL
 OR OBJECT_ID('dbo.trg_W6_InventoryTypedRefs','TR') IS NULL
 THROW 53201,'v1.1 hardening not installed',1;
IF (SELECT COUNT(*) FROM dbo.InventoryLog WHERE reference_type='usage')<>3000
 THROW 53202,'Converted typed references missing',1;
IF EXISTS(SELECT 1 FROM dbo.InventoryLog l LEFT JOIN dbo.TokenUsageLogs u
          ON u.log_id=l.reference_id WHERE l.reference_type='usage'
  AND (u.log_id IS NULL OR u.account_id<>l.account_id
    OR u.used_at<>l.created_at
    OR l.change_amount<>-CONVERT(BIGINT,u.upstream_tokens_consumed)))
 THROW 53203,'Existing typed event reference inconsistency',1;
PRINT 'PASS X01 all historical usage audit links match account, time and amount';
GO

-- Positive: real owner-controlled payment adds funds once; external transaction
-- rolls all effects back, preserving baseline.
DECLARE @order_id INT,@before_balance BIGINT,@credited BIGINT;
SELECT @before_balance=remaining_tokens FROM dbo.TokenBalances
 WHERE user_id=1 AND model_provider='OpenAI';
SELECT @credited=token_amount FROM dbo.Products WHERE product_id=1;
BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.usp_W5_CreateRegisteredOrder @user_id=1;
 SELECT @order_id=MAX(order_id) FROM dbo.Orders WHERE user_id=1 AND status='pending';
 EXEC dbo.usp_W5_AddMergedOrderItem @order_id=@order_id,@product_id=1,@quantity=1;
 EXECUTE AS USER='hub_manager_demo';
 EXEC dbo.usp_W6_PayPendingOrder @order_id=@order_id;
 REVERT;
 IF (SELECT remaining_tokens FROM dbo.TokenBalances
     WHERE user_id=1 AND model_provider='OpenAI')<>@before_balance+@credited
    OR NOT EXISTS(SELECT 1 FROM dbo.Orders
       WHERE order_id=@order_id AND status='paid' AND paid_at IS NOT NULL)
    THROW 53204,'Controlled payment failed to credit user/provider',1;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 IF USER_NAME()<>'dbo' REVERT;
 THROW;
END CATCH;
IF (SELECT remaining_tokens FROM dbo.TokenBalances
 WHERE user_id=1 AND model_provider='OpenAI')<>@before_balance
 THROW 53205,'Payment rollback left a balance change',1;
PRINT 'PASS X02 manager-managed payment credits exactly once and rolls back';
GO

DECLARE @log_id INT,@base_count BIGINT=(SELECT COUNT_BIG(*) FROM dbo.TokenUsageLogs);
BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.usp_W5_RecordUsage @user_id=1,@product_id=1,@account_id=1,
 @tokens_used=2,@upstream_tokens_used=3,@api_endpoint='w6_harden_test';
 SELECT @log_id=MAX(log_id) FROM dbo.TokenUsageLogs
 WHERE api_endpoint='w6_harden_test';
 IF @log_id IS NULL OR NOT EXISTS(
  SELECT 1 FROM dbo.InventoryLog l JOIN dbo.TokenUsageLogs u
    ON u.log_id=l.reference_id
  WHERE l.reference_type='usage' AND u.log_id=@log_id AND l.account_id=u.account_id
    AND l.created_at=u.used_at
    AND l.change_amount=-CONVERT(BIGINT,u.upstream_tokens_consumed))
  THROW 53206,'Managed consumption failed to produce typed ledger link',1;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
IF (SELECT COUNT_BIG(*) FROM dbo.TokenUsageLogs)<>@base_count
 THROW 53207,'Consumption rollback left an event',1;
PRINT 'PASS X03 new controlled usage has exact typed audit link and rollback';
GO

-- Negative: forbidden manual reference with a numeric target.
DECLARE @got INT=0;
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.InventoryLog(account_id,change_type,change_amount,reference_type,reference_id)
 VALUES(1,'adjustment',1,'manual',1);
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
END CATCH;
IF @got<>53007 THROW 53208,'Opaque numeric manual reference was not rejected',1;
PRINT 'PASS X04 invalid manual reference denied with 53007';
GO

DECLARE @got INT=0;
BEGIN TRY
 BEGIN TRANSACTION;
 UPDATE dbo.TokenUsageLogs SET used_at=used_at WHERE log_id=1;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
END CATCH;
IF @got<>53008 THROW 53209,'Historical event UPDATE not rejected',1;
PRINT 'PASS X05 usage event is append-only';
GO

DECLARE @got INT=0,@previous BIGINT=
 (SELECT remaining_tokens FROM dbo.TokenBalances WHERE user_id=1 AND model_provider='OpenAI');
BEGIN TRY
 BEGIN TRANSACTION;
 EXECUTE AS USER='hub_manager_demo';
 UPDATE dbo.TokenBalances SET remaining_tokens=remaining_tokens+1
 WHERE user_id=1 AND model_provider='OpenAI';
 REVERT;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 IF USER_NAME()<>'dbo' REVERT;
END CATCH;
IF @got<>53117
 THROW 53210,'Direct manager balance mutation not rejected',1;
IF (SELECT remaining_tokens FROM dbo.TokenBalances
 WHERE user_id=1 AND model_provider='OpenAI')<>@previous
 THROW 53211,'Rejected mutation changed balance',1;
PRINT 'PASS X06 manager direct balance adjustment denied';
GO

DECLARE @got INT=0;
BEGIN TRY
 BEGIN TRANSACTION;
 EXECUTE AS USER='hub_manager_demo';
 UPDATE dbo.UpstreamAccount SET used_quota=used_quota+1 WHERE account_id=1;
 REVERT;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 IF USER_NAME()<>'dbo' REVERT;
END CATCH;
IF @got<>53113
 THROW 53212,'Direct manager quota mutation not rejected',1;
PRINT 'PASS X07 manager direct quota adjustment denied';
GO

DECLARE @got INT=0;
BEGIN TRY
 BEGIN TRANSACTION;
 UPDATE dbo.Users SET created_at='2029-01-01' WHERE user_id=1;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
END CATCH;
IF @got<>53110
 THROW 53213,'Retroactive user registration mutation not rejected',1;
PRINT 'PASS X08 user history cannot be made inconsistent';
GO

DECLARE @got INT=0;
BEGIN TRY
 BEGIN TRANSACTION;
 UPDATE dbo.UpstreamAccount SET provider='Claude' WHERE account_id=1;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
END CATCH;
IF @got<>53112
 THROW 53214,'Retroactive provider mutation not rejected',1;
PRINT 'PASS X09 upstream account provider cannot invalidate usage';
GO

DECLARE @got INT=0,@oid INT;
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.Orders(user_id,total_amount,total_tokens,status)
 VALUES(1,0,0,'pending');
 SET @oid=CONVERT(INT,SCOPE_IDENTITY());
 EXECUTE AS USER='hub_manager_demo';
 UPDATE dbo.Orders SET status='paid',paid_at=CONVERT(DATETIME2(0),SYSDATETIME())
 WHERE order_id=@oid;
 REVERT;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 IF USER_NAME()<>'dbo' REVERT;
END CATCH;
IF @got NOT IN (53115,51920)
 THROW 53215,'Uncontrolled payment/finalization was not rejected',1;
PRINT 'PASS X10 manager direct order finalization blocked';
GO

IF @@TRANCOUNT<>0 OR USER_NAME()<>'dbo'
 THROW 53216,'Open transaction or impersonation after regression',1;
IF (SELECT COUNT(*) FROM dbo.InventoryLog WHERE reference_type='usage')<>3000
 THROW 53217,'Regression did not roll back all inserted reference events',1;
PRINT 'PASS V1.1 HARDENED REGRESSION X01-X10';
GO
