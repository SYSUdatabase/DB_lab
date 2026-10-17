-- SQL-side refundable amount and reserved token debit.
-- Only unconsumed tokens are refundable. Paid cash still needs external transfer.
:on error exit
SET NOCOUNT ON;
IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
 THROW 54200,'Wrong v1.1 sandbox',1;
IF OBJECT_ID('dbo.RefundLedger','U') IS NULL
 OR OBJECT_ID('dbo.OrderTokenLots','U') IS NULL
 OR OBJECT_ID('dbo.usp_W6_RequestRefund','P') IS NOT NULL
 THROW 54201,'Refund schema missing or procedure already installed',1;
GO
CREATE PROCEDURE dbo.usp_W6_RequestRefund
 @order_id INT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
  THROW 54202,'Wrong refund database',1;
 DECLARE @user_id INT,@status VARCHAR(20),@paid_at DATETIME2(0),
         @total_eligible BIGINT,@total_consumed BIGINT,
         @total_issued BIGINT,@refund_amount DECIMAL(10,2),
         @now DATETIME2(0)=CONVERT(DATETIME2(0),SYSDATETIME());
 DECLARE @lines TABLE (
   detail_id INT PRIMARY KEY, provider VARCHAR(50) NOT NULL,
   available_tokens BIGINT NOT NULL,consumed BIGINT NOT NULL,issued BIGINT NOT NULL,
   refund_amount DECIMAL(10,2) NOT NULL
 );
 BEGIN TRY
  SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  BEGIN TRANSACTION;
  SELECT @user_id=o.user_id,@status=o.status,@paid_at=o.paid_at
    FROM dbo.Orders o WITH(UPDLOCK,HOLDLOCK) WHERE o.order_id=@order_id;
  IF @user_id IS NULL THROW 54203,'Order missing',1;
  -- Retried requests are idempotent; no double money or tokens.
  IF EXISTS(SELECT 1 FROM dbo.RefundLedger WITH(UPDLOCK,HOLDLOCK)
            WHERE order_id=@order_id)
  BEGIN
   COMMIT TRANSACTION;
   SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
   SELECT order_id,refund_id,refund_amount,refundable_tokens,
          consumed_tokens,payout_state,external_payout_ref
   FROM dbo.RefundLedger WHERE order_id=@order_id;
   RETURN;
  END;
  IF @status<>'paid' OR @paid_at IS NULL
   THROW 54204,'Refund requires a paid, not previously refunded order',1;
  IF EXISTS(SELECT 1 FROM dbo.OrderDetails d WHERE d.order_id=@order_id
     AND NOT EXISTS(SELECT 1 FROM dbo.OrderTokenLots l WHERE l.detail_id=d.detail_id))
   THROW 54205,'Paid order missing token batch provenance',1;
  INSERT @lines(detail_id,provider,available_tokens,consumed,issued,refund_amount)
  SELECT d.detail_id,p.model_provider,
         l.issued_tokens-l.consumed_tokens-l.refunded_tokens,
         l.consumed_tokens,l.issued_tokens,
         CONVERT(DECIMAL(10,2),ROUND(
          CONVERT(DECIMAL(28,8),d.subtotal)*
           CONVERT(DECIMAL(28,8),l.issued_tokens-l.consumed_tokens-l.refunded_tokens)/
            NULLIF(CONVERT(DECIMAL(28,8),l.issued_tokens),0),2))
   FROM dbo.OrderDetails d
   JOIN dbo.OrderTokenLots l WITH(UPDLOCK,HOLDLOCK) ON l.detail_id=d.detail_id
   JOIN dbo.Products p ON p.product_id=d.product_id
   WHERE d.order_id=@order_id;
  SELECT @total_eligible=SUM(available_tokens),
         @total_consumed=SUM(consumed),
         @total_issued=SUM(issued),
         @refund_amount=SUM(refund_amount)
   FROM @lines;
  IF @total_eligible IS NULL OR @total_eligible<=0 OR @refund_amount<=0
   THROW 54206,'Order has no refundable unconsumed tokens',1;
  IF @total_issued<>(SELECT total_tokens FROM dbo.Orders WHERE order_id=@order_id)
   THROW 54207,'Purchased lots and order token snapshot differ',1;
  DECLARE @credit TABLE(provider VARCHAR(50) PRIMARY KEY,tokens BIGINT NOT NULL);
  INSERT @credit SELECT provider,SUM(available_tokens)
    FROM @lines GROUP BY provider;
  IF EXISTS(SELECT 1 FROM @credit c
     LEFT JOIN dbo.TokenBalances b WITH(UPDLOCK,HOLDLOCK)
      ON b.user_id=@user_id AND b.model_provider=c.provider
     WHERE b.balance_id IS NULL OR b.remaining_tokens<c.tokens)
   THROW 54208,'Refund would withdraw more tokens than the member owns',1;
  -- Reserve all remaining tokens for this order; consumed tokens cannot be refunded.
  UPDATE l SET refunded_tokens=l.refunded_tokens+x.available_tokens
  FROM dbo.OrderTokenLots l JOIN @lines x ON x.detail_id=l.detail_id;
  UPDATE b SET remaining_tokens=b.remaining_tokens-c.tokens,updated_at=@now
  FROM dbo.TokenBalances b JOIN @credit c ON c.provider=b.model_provider
   WHERE b.user_id=@user_id;
  IF @@ROWCOUNT<>(SELECT COUNT(*) FROM @credit)
   THROW 54209,'Refund affected an unexpected number of balance rows',1;
  INSERT dbo.RefundLedger(order_id,requested_at,refund_amount,
        refundable_tokens,consumed_tokens,payout_state)
  VALUES(@order_id,@now,@refund_amount,@total_eligible,@total_consumed,
         'awaiting_transfer');
  UPDATE dbo.Orders SET status=CASE WHEN @total_consumed=0
        THEN 'refunded' ELSE 'partially_refunded' END
  WHERE order_id=@order_id AND status='paid';
  IF @@ROWCOUNT<>1 THROW 54210,'Paid order changed concurrently',1;
  COMMIT TRANSACTION;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  SELECT order_id,refund_id,refund_amount,refundable_tokens,consumed_tokens,
         payout_state,external_payout_ref
  FROM dbo.RefundLedger WHERE order_id=@order_id;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  THROW;
 END CATCH;
END;
GO
CREATE PROCEDURE dbo.usp_W6_AttestRefundPayout
 @order_id INT,
 @external_payout_ref VARCHAR(120),
 @confirmed_employee_id INT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
  THROW 54220,'Wrong payout ledger database',1;
 -- This records an OUTSIDE payment processor's confirmed transfer reference.
 -- SQL Server itself does not send the money and cannot verify a gateway receipt.
 IF @external_payout_ref IS NULL OR LEN(TRIM(@external_payout_ref))<6
  THROW 54221,'A nonempty external payout reference is mandatory',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Employees e JOIN dbo.Roles r ON r.role_id=e.role_id
   WHERE e.employee_id=@confirmed_employee_id AND e.status='active'
     AND r.role_name IN ('admin','staff'))
  THROW 54222,'An active financial-review employee must attest the payout',1;
 DECLARE @status VARCHAR(24),@existing VARCHAR(120);
 BEGIN TRY
  SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  BEGIN TRANSACTION;
  SELECT @status=payout_state,@existing=external_payout_ref
    FROM dbo.RefundLedger WITH(UPDLOCK,HOLDLOCK) WHERE order_id=@order_id;
  IF @status IS NULL THROW 54223,'No refund liability exists',1;
  IF @status='settled'
  BEGIN
   IF @existing<>@external_payout_ref
    THROW 54224,'Refund already settled with a different payout reference',1;
   COMMIT;
   SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
   SELECT order_id,refund_amount,payout_state,external_payout_ref
    FROM dbo.RefundLedger WHERE order_id=@order_id;
   RETURN;
  END;
  IF EXISTS(SELECT 1 FROM dbo.RefundLedger WHERE
    external_payout_ref=@external_payout_ref AND order_id<>@order_id)
   THROW 54225,'This payout reference was used for a different refund',1;
  UPDATE dbo.RefundLedger
   SET payout_state='settled',external_payout_ref=@external_payout_ref,
       settled_at=CONVERT(DATETIME2(0),SYSDATETIME())
   WHERE order_id=@order_id AND payout_state='awaiting_transfer';
  IF @@ROWCOUNT<>1 THROW 54226,'Concurrent payout change detected',1;
  COMMIT;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  SELECT order_id,refund_amount,payout_state,external_payout_ref
    FROM dbo.RefundLedger WHERE order_id=@order_id;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  THROW;
 END CATCH;
END;
GO
GRANT EXECUTE ON dbo.usp_W6_RequestRefund TO hub_manager;
GRANT EXECUTE ON dbo.usp_W6_AttestRefundPayout TO hub_manager;
PRINT 'PASS refund request idempotency, proportional unconsumed tokens, and payout evidence ledger';
GO
