-- Refund: proportional unconsumed tokens, no double refund, cash liability,
-- external payout attestation, legacy refunded rows left unchanged.
-- ALL test writes rolled back, never asserts transfer of external money.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
 THROW 54300,'Wrong v1.1 sandbox',1;
IF (SELECT COUNT(*) FROM dbo.OrderTokenLots)<>158
 OR EXISTS(SELECT 1 FROM dbo.RefundLedger)
 THROW 54301,'Wrong refund-test initial state',1;
IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>17
 OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled=0 AND is_not_trusted=0)<>20
 THROW 54302,'Refund schema drift',1;
IF (SELECT SUM(issued_tokens-consumed_tokens-refunded_tokens)
    FROM dbo.OrderTokenLots)<>(SELECT SUM(remaining_tokens) FROM dbo.TokenBalances)
 THROW 54303,'Source token lots differ from user balances',1;
PRINT 'PASS RF01 legacy paid lot balances match all live TokenBalances';
GO

DECLARE @u INT,@oid INT,@ref INT,@pre BIGINT,@after BIGINT,
        @amount DECIMAL(10,2),@tokens BIGINT,@spent BIGINT,@status VARCHAR(20);
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.Users(username,password_hash,email,status,created_at,updated_at)
 VALUES('refund_test_user_a',REPLICATE('x',60),'refund-test-a@example.invalid','active',
        CONVERT(DATETIME2(0),SYSDATETIME()),CONVERT(DATETIME2(0),SYSDATETIME()));
 SET @u=CONVERT(INT,SCOPE_IDENTITY());
 EXEC dbo.usp_W5_CreateRegisteredOrder @user_id=@u;
 SELECT @oid=MAX(order_id) FROM dbo.Orders WHERE user_id=@u AND status='pending';
 EXEC dbo.usp_W5_AddMergedOrderItem @order_id=@oid,@product_id=2,@quantity=1;
 EXECUTE AS USER='hub_manager_demo';
 EXEC dbo.usp_W6_PayPendingOrder @order_id=@oid;
 REVERT;
 IF (SELECT SUM(issued_tokens) FROM dbo.OrderTokenLots
 JOIN dbo.OrderDetails d ON d.detail_id=dbo.OrderTokenLots.detail_id
 WHERE d.order_id=@oid)<>100000
 THROW 54304,'Paid order did not issue exact 100k token lot',1;
 EXEC dbo.usp_W5_RecordUsage @user_id=@u,@product_id=2,@account_id=1,
  @tokens_used=20000,@upstream_tokens_used=24000,@api_endpoint='refund-case-a';
 IF (SELECT remaining_tokens FROM dbo.TokenBalances
 WHERE user_id=@u AND model_provider='OpenAI')<>80000
 THROW 54305,'Consumption did not debit only new order lot',1;
 EXECUTE AS USER='hub_manager_demo';
 EXEC dbo.usp_W6_RequestRefund @order_id=@oid;
 REVERT;
 SELECT @ref=refund_id,@amount=refund_amount,@tokens=refundable_tokens,
  @spent=consumed_tokens FROM dbo.RefundLedger WHERE order_id=@oid;
 SELECT @status=status FROM dbo.Orders WHERE order_id=@oid;
 IF @amount<>5.52 OR @tokens<>80000 OR @spent<>20000
  OR @status<>'partially_refunded'
  OR (SELECT remaining_tokens FROM dbo.TokenBalances
      WHERE user_id=@u AND model_provider='OpenAI')<>0
  OR NOT EXISTS(SELECT 1 FROM dbo.RefundLedger WHERE order_id=@oid
      AND payout_state='awaiting_transfer' AND settled_at IS NULL)
  THROW 54306,'Partial refund amount, paid liability or token deduction incorrect',1;
 SET @pre=(SELECT COUNT(*) FROM dbo.RefundLedger);
 EXECUTE AS USER='hub_manager_demo';
 EXEC dbo.usp_W6_RequestRefund @order_id=@oid;
 REVERT;
 IF (SELECT COUNT(*) FROM dbo.RefundLedger)<>@pre OR
    (SELECT remaining_tokens FROM dbo.TokenBalances
     WHERE user_id=@u AND model_provider='OpenAI')<>0
  THROW 54307,'Repeated refund changed balances or created duplicate payout',1;
 EXECUTE AS USER='hub_manager_demo';
 EXEC dbo.usp_W6_AttestRefundPayout @order_id=@oid,
   @external_payout_ref='TEST-GATEWAY-PAYOUT-REF-A',@confirmed_employee_id=1;
 REVERT;
 IF NOT EXISTS(SELECT 1 FROM dbo.RefundLedger WHERE order_id=@oid
    AND payout_state='settled'
    AND external_payout_ref='TEST-GATEWAY-PAYOUT-REF-A' AND settled_at IS NOT NULL)
 THROW 54308,'External settlement evidence was not recorded',1;
 EXECUTE AS USER='hub_manager_demo';
 EXEC dbo.usp_W6_AttestRefundPayout @order_id=@oid,
   @external_payout_ref='TEST-GATEWAY-PAYOUT-REF-A',@confirmed_employee_id=1;
 REVERT;
 IF (SELECT COUNT(*) FROM dbo.RefundLedger WHERE order_id=@oid)<>1
 THROW 54309,'Duplicate payout attestation created duplicate refund row',1;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 IF USER_NAME()<>'dbo' REVERT;
 THROW;
END CATCH;
PRINT 'PASS RF02 partial consumption: 20k nonrefundable, 80k clawback, $5.52 pending refund; idempotent settlement';
GO

DECLARE @u INT,@oid INT,@err INT=0;
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.Users(username,password_hash,email,status,created_at,updated_at)
 VALUES('refund_test_user_b',REPLICATE('x',60),'refund-test-b@example.invalid','active',
        CONVERT(DATETIME2(0),SYSDATETIME()),CONVERT(DATETIME2(0),SYSDATETIME()));
 SET @u=CONVERT(INT,SCOPE_IDENTITY());
 EXEC dbo.usp_W5_CreateRegisteredOrder @user_id=@u;
 SELECT @oid=MAX(order_id) FROM dbo.Orders WHERE user_id=@u AND status='pending';
 EXEC dbo.usp_W5_AddMergedOrderItem @order_id=@oid,@product_id=2,@quantity=1;
 EXECUTE AS USER='hub_manager_demo';
 EXEC dbo.usp_W6_PayPendingOrder @order_id=@oid;
 EXEC dbo.usp_W6_RequestRefund @order_id=@oid;
 REVERT;
 IF NOT EXISTS(SELECT 1 FROM dbo.RefundLedger
  WHERE order_id=@oid AND refund_amount=6.90 AND refundable_tokens=100000
    AND consumed_tokens=0 AND payout_state='awaiting_transfer')
 OR (SELECT status FROM dbo.Orders WHERE order_id=@oid)<>'refunded'
 OR (SELECT remaining_tokens FROM dbo.TokenBalances
  WHERE user_id=@u AND model_provider='OpenAI')<>0
 THROW 54310,'Full unused order must refund full cash amount and all its tokens',1;
 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 IF USER_NAME()<>'dbo' REVERT;
 THROW;
END CATCH;
PRINT 'PASS RF03 unused order refunds all 100k tokens and full $6.90 as transfer liability';
GO

DECLARE @got INT=0;
BEGIN TRY
 EXECUTE AS USER='hub_manager_demo';
 EXEC dbo.usp_W6_RequestRefund @order_id=30; -- Legacy refunded example.
 REVERT;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF USER_NAME()<>'dbo' REVERT;
END CATCH;
IF @got<>54204
 THROW 54311,'Legacy already-refunded order must not be paid twice',1;
PRINT 'PASS RF04 old refunded order rejects duplicate refund, no invented payout';
GO

DECLARE @got INT=0;
BEGIN TRY
 EXECUTE AS USER='hub_manager_demo';
 INSERT dbo.RefundLedger(order_id,requested_at,refund_amount,
  refundable_tokens,consumed_tokens)
 VALUES(30,CONVERT(DATETIME2(0),SYSDATETIME()),1,100,0);
 REVERT;
END TRY
BEGIN CATCH
 SET @got=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 IF USER_NAME()<>'dbo' REVERT;
END CATCH;
IF @got NOT IN (229,54012)
 THROW 54312,'Manager must not insert refund ledger directly',1;
PRINT 'PASS RF05 direct forged cash-refund record blocked';
GO

DECLARE @bad INT=0;
IF (SELECT COUNT(*) FROM dbo.RefundLedger)<>0 SET @bad=1;
IF (SELECT COUNT(*) FROM dbo.OrderTokenLots)<>158 SET @bad=1;
IF (SELECT COUNT(*) FROM dbo.TokenUsageLogs)<>3000 SET @bad=1;
IF @@TRANCOUNT<>0 SET @bad=1;
IF USER_NAME()<>'dbo' SET @bad=1;
IF @bad<>0 THROW 54313,'Refund regression must leave source rows unchanged',1;
PRINT 'PASS RF06 rollback, original history and balances preserved';
PRINT 'PASS V1.1 REFUND REGRESSION RF01-RF06';
GO
