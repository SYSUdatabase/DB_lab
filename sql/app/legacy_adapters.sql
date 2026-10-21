-- App-isolated static adaptations of v11 procedures.
-- Business transactions/errors are unchanged. Optional flags suppress result sets,
-- preventing INSERT EXEC from masking a legacy ROLLBACK/THROW failure.
-- Existing callers retain emit_result=1 and the original result shapes.
CREATE OR ALTER PROCEDURE dbo.usp_W5_CreateRegisteredOrder
 @user_id INT,
 @emit_result BIT=1,
 @app_result_id INT=NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'$(DatabaseName)'
  THROW 52122,'Wrong database',1;
 IF @user_id IS NULL OR NOT EXISTS(
   SELECT 1 FROM dbo.Users WHERE user_id=@user_id AND status='active')
  THROW 52123,'Existing active Users record required before order',1;
 DECLARE @id INT;
 BEGIN TRY
  BEGIN TRAN;
  INSERT dbo.Orders(user_id,total_amount,total_tokens,status)
  VALUES(@user_id,0,0,'pending');
  SET @id=CONVERT(INT,SCOPE_IDENTITY());
  COMMIT TRAN;
  SET @app_result_id=@id;
 IF @emit_result=1 SELECT @id AS order_id;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  THROW;
 END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_W5_AddMergedOrderItem
 @order_id INT,
 @product_id INT,
 @quantity INT,
 @emit_result BIT=1,
 @app_result_id INT=NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'$(DatabaseName)'
  THROW 52124,'Wrong database',1;
 IF @quantity IS NULL OR @quantity<=0
  THROW 52125,'Quantity must be positive',1;
 DECLARE @price DECIMAL(10,2),@token_amount INT,
     @oldqty INT,@unitprice DECIMAL(10,2),@oldtoken INT;
 BEGIN TRY
  SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  BEGIN TRAN;
  IF NOT EXISTS(SELECT 1 FROM dbo.Orders WITH(UPDLOCK,HOLDLOCK)
      WHERE order_id=@order_id AND status='pending')
   THROW 52126,'Order must be an existing pending draft',1;
  SELECT @price=price,@token_amount=token_amount
  FROM dbo.Products WITH(UPDLOCK,HOLDLOCK)
  WHERE product_id=@product_id AND status='active';
  IF @price IS NULL OR @token_amount IS NULL
   THROW 52127,'Product missing or inactive',1;
  SELECT @oldqty=quantity,@unitprice=unit_price,@oldtoken=tokens_per_unit
  FROM dbo.OrderDetails WITH(UPDLOCK,HOLDLOCK)
  WHERE order_id=@order_id AND product_id=@product_id;
  IF @oldqty IS NOT NULL
  BEGIN
   IF @oldqty>2147483647-@quantity
    THROW 52128,'Quantity overflow',1;
   -- Retain the first recorded purchase price/token snapshot.
   UPDATE dbo.OrderDetails SET quantity=@oldqty+@quantity,
      subtotal=CONVERT(DECIMAL(10,2),CONVERT(DECIMAL(18,2),@oldqty+@quantity)*@unitprice),
      total_tokens=CONVERT(BIGINT,@oldqty+@quantity)*@oldtoken
   WHERE order_id=@order_id AND product_id=@product_id;
  END
  ELSE
  BEGIN
   INSERT dbo.OrderDetails(order_id,product_id,quantity,unit_price,
      subtotal,tokens_per_unit,total_tokens)
   VALUES(@order_id,@product_id,@quantity,@price,
      CONVERT(DECIMAL(10,2),CONVERT(DECIMAL(18,2),@quantity)*@price),
      @token_amount,CONVERT(BIGINT,@quantity)*@token_amount);
  END;
  UPDATE o SET total_amount=x.amount,total_tokens=x.tokens
  FROM dbo.Orders o CROSS APPLY (
   SELECT SUM(d.subtotal) amount,SUM(d.total_tokens) tokens
   FROM dbo.OrderDetails d WHERE d.order_id=@order_id
  ) x
  WHERE o.order_id=@order_id;
  IF @@ROWCOUNT<>1 THROW 52129,'Header not updated',1;
  COMMIT TRAN;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  SET @app_result_id=(SELECT detail_id FROM dbo.OrderDetails WHERE order_id=@order_id AND product_id=@product_id);
  IF @emit_result=1 SELECT detail_id,order_id,product_id,quantity,subtotal,total_tokens
  FROM dbo.OrderDetails WHERE order_id=@order_id AND product_id=@product_id;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  THROW;
 END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_W5_RecordUsage
 @user_id INT,
 @product_id INT,
 @account_id INT,
 @tokens_used INT,
 @upstream_tokens_used INT,
 @api_endpoint VARCHAR(255)=NULL,
 @emit_result BIT=1,
 @app_result_id INT=NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'$(DatabaseName)'
  THROW 51952,'Wrong usage database',1;
 IF @tokens_used<=0 OR @upstream_tokens_used<=0
  THROW 51953,'Usage amounts must be positive',1;
 DECLARE @ts DATETIME2(0)=CONVERT(DATETIME2(0),SYSDATETIME());
 DECLARE @provider VARCHAR(50),@account_provider VARCHAR(50),@ucreated DATETIME2(0),
         @acct_created DATETIME2(0),@acct_expires DATETIME2(0),
         @bal BIGINT,@inv BIGINT,@used BIGINT,@total BIGINT,@latest DATETIME2(0),
         @log_id INT;
 BEGIN TRY
  SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  BEGIN TRANSACTION;
  SELECT @ucreated=created_at FROM dbo.Users WITH(UPDLOCK,HOLDLOCK)
     WHERE user_id=@user_id AND status='active';
  SELECT @provider=model_provider FROM dbo.Products WITH(UPDLOCK,HOLDLOCK)
     WHERE product_id=@product_id AND status='active';
  SELECT @account_provider=provider,@acct_created=created_at,
         @acct_expires=expires_at,@used=used_quota,@total=total_quota
     FROM dbo.UpstreamAccount WITH(UPDLOCK,HOLDLOCK)
     WHERE account_id=@account_id AND status='active';
  IF @ucreated IS NULL OR @provider IS NULL OR @account_provider IS NULL
   THROW 51954,'User, product or account unavailable',1;
  IF @provider<>@account_provider OR @ts<@ucreated OR @ts<@acct_created
     OR (@acct_expires IS NOT NULL AND @ts>=@acct_expires)
   THROW 51955,'Provider, registration or account usage interval invalid',1;
  SELECT @bal=remaining_tokens FROM dbo.TokenBalances WITH(UPDLOCK,HOLDLOCK)
   WHERE user_id=@user_id AND model_provider=@provider;
  SELECT @inv=current_quota FROM dbo.Inventory WITH(UPDLOCK,HOLDLOCK)
   WHERE account_id=@account_id;
  IF @bal IS NULL OR @inv IS NULL OR @bal<@tokens_used
     OR @inv<@upstream_tokens_used OR @total-@used<@upstream_tokens_used
     OR @inv<>@total-@used
   THROW 51956,'Insufficient balance, quota or inconsistent inventory',1;
  SELECT @latest=MAX(l.used_at) FROM dbo.TokenUsageLogs l WITH(HOLDLOCK)
    JOIN dbo.Products p ON p.product_id=l.product_id
    WHERE l.user_id=@user_id AND p.model_provider=@provider;
  IF @latest IS NOT NULL AND @ts<@latest
   THROW 51957,'Out-of-order new usage event',1;
  UPDATE dbo.TokenBalances SET remaining_tokens=remaining_tokens-@tokens_used,
        updated_at=@ts WHERE user_id=@user_id AND model_provider=@provider;
  UPDATE dbo.UpstreamAccount SET used_quota=used_quota+@upstream_tokens_used,
        updated_at=@ts WHERE account_id=@account_id;
  UPDATE dbo.Inventory SET current_quota=current_quota-@upstream_tokens_used,
        last_updated_at=@ts WHERE account_id=@account_id;
  INSERT dbo.TokenUsageLogs(user_id,product_id,account_id,tokens_used,
       upstream_tokens_consumed,api_endpoint,used_at)
  VALUES(@user_id,@product_id,@account_id,@tokens_used,
       @upstream_tokens_used,@api_endpoint,@ts);
  SET @log_id=CONVERT(INT,SCOPE_IDENTITY());
  INSERT dbo.InventoryLog(account_id,change_type,change_amount,
        reference_type,reference_id,reason,operator_id,created_at)
  VALUES(@account_id,'consumption',-CONVERT(BIGINT,@upstream_tokens_used),
         'usage',@log_id,N'API token usage',NULL,@ts);
  DECLARE @day DATE=CONVERT(DATE,@ts),
          @monday DATE=DATEADD(DAY,-DATEDIFF(DAY,CONVERT(DATE,'19000101'),CONVERT(DATE,@ts))%7,CONVERT(DATE,@ts)),
          @month DATE=DATEFROMPARTS(YEAR(@ts),MONTH(@ts),1);
  DECLARE @period TABLE(period_type VARCHAR(10),period_start DATE,period_end DATE,
        PRIMARY KEY(period_type,period_start));
  INSERT @period VALUES('daily',@day,@day),('weekly',@monday,DATEADD(DAY,6,@monday)),
        ('monthly',@month,EOMONTH(@month));
  INSERT dbo.UsagePeriod(period_type,period_start,period_end)
  SELECT t.period_type,t.period_start,t.period_end FROM @period t
  WHERE NOT EXISTS(SELECT 1 FROM dbo.UsagePeriod p WITH(UPDLOCK,HOLDLOCK)
        WHERE p.period_type=t.period_type AND p.period_start=t.period_start);
  UPDATE s SET s.total_tokens_used=s.total_tokens_used+@tokens_used,
     s.total_upstream_consumed=s.total_upstream_consumed+@upstream_tokens_used,
     s.request_count=s.request_count+1,s.last_updated_at=@ts
  FROM dbo.UsageSummaryCore s JOIN @period p
   ON p.period_type=s.period_type AND p.period_start=s.period_start
  WHERE s.user_id=@user_id AND s.product_id=@product_id;
  INSERT dbo.UsageSummaryCore(user_id,product_id,period_type,period_start,
         total_tokens_used,total_upstream_consumed,request_count,last_updated_at)
  SELECT @user_id,@product_id,p.period_type,p.period_start,@tokens_used,
         @upstream_tokens_used,1,@ts FROM @period p
  WHERE NOT EXISTS (
    SELECT 1 FROM dbo.UsageSummaryCore s WITH(UPDLOCK,HOLDLOCK)
     WHERE s.user_id=@user_id AND s.product_id=@product_id
      AND s.period_type=p.period_type AND s.period_start=p.period_start);
  -- FIFO consumes the oldest unrefunded purchased token batches.
  -- SERIALIZABLE + HOLDLOCK prevent concurrent consumption/refund overdraw.
  DECLARE @lot_due BIGINT=CONVERT(BIGINT,@tokens_used),
          @lot_detail INT,@lot_available BIGINT,@lot_slice BIGINT;
  DECLARE lot_debit CURSOR LOCAL FAST_FORWARD FOR
   SELECT b.detail_id,b.issued_tokens-b.consumed_tokens-b.refunded_tokens
   FROM dbo.OrderTokenLots b WITH(UPDLOCK,HOLDLOCK)
   JOIN dbo.OrderDetails d ON d.detail_id=b.detail_id
   JOIN dbo.Orders o ON o.order_id=d.order_id
   JOIN dbo.Products p ON p.product_id=d.product_id
   WHERE o.user_id=@user_id AND p.model_provider=@provider
     AND b.issued_tokens>b.consumed_tokens+b.refunded_tokens
   ORDER BY b.credited_at,b.detail_id;
  OPEN lot_debit;
  FETCH NEXT FROM lot_debit INTO @lot_detail,@lot_available;
  WHILE @@FETCH_STATUS=0 AND @lot_due>0
  BEGIN
   SET @lot_slice=CASE WHEN @lot_available<@lot_due
                       THEN @lot_available ELSE @lot_due END;
   UPDATE dbo.OrderTokenLots SET consumed_tokens=consumed_tokens+@lot_slice
   WHERE detail_id=@lot_detail;
   SET @lot_due=@lot_due-@lot_slice;
   FETCH NEXT FROM lot_debit INTO @lot_detail,@lot_available;
  END;
  CLOSE lot_debit;
  DEALLOCATE lot_debit;
  IF @lot_due<>0 THROW 54101,'Insufficient unrefunded token lots',1;
  COMMIT TRANSACTION;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  SET @app_result_id=@log_id;
  IF @emit_result=1 SELECT @log_id AS log_id,@provider AS model_provider,@ts AS used_at;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  THROW;
 END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_W6_PayPendingOrder
 @order_id INT,
 @emit_result BIT=1,
 @app_result_id INT=NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'$(DatabaseName)'
  THROW 53122,'Wrong payment database',1;
 DECLARE @now DATETIME2(0)=CONVERT(DATETIME2(0),SYSDATETIME()),
         @user_id INT,@amount DECIMAL(10,2),@total BIGINT;
 BEGIN TRY
  SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  BEGIN TRANSACTION;
  SELECT @user_id=o.user_id,@amount=o.total_amount,@total=o.total_tokens
  FROM dbo.Orders o WITH(UPDLOCK,HOLDLOCK)
  WHERE o.order_id=@order_id AND o.status='pending' AND o.created_at<=@now;
  IF @user_id IS NULL
   THROW 53123,'Payment requires an existing pending order',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Users u
    WHERE u.user_id=@user_id AND u.status='active' AND u.created_at<=@now)
   THROW 53124,'Registered active buyer required',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.OrderDetails WHERE order_id=@order_id)
   THROW 53125,'Cannot pay an empty draft',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.OrderDetails d
     JOIN dbo.Products p ON p.product_id=d.product_id
     WHERE d.order_id=@order_id AND p.model_provider IN ('OpenAI','Claude','Gemini','Other'))
   THROW 53126,'No creditable product',1;
  IF (SELECT SUM(d.subtotal) FROM dbo.OrderDetails d WHERE d.order_id=@order_id)<>@amount
    OR (SELECT SUM(d.total_tokens) FROM dbo.OrderDetails d WHERE d.order_id=@order_id)<>@total
   THROW 53127,'Order amounts do not match detail snapshots',1;
  DECLARE @credit TABLE (provider VARCHAR(50) PRIMARY KEY, tokens BIGINT NOT NULL);
  INSERT @credit
   SELECT p.model_provider,SUM(d.total_tokens) FROM dbo.OrderDetails d
   JOIN dbo.Products p ON p.product_id=d.product_id WHERE d.order_id=@order_id
   GROUP BY p.model_provider;
  UPDATE b SET remaining_tokens=b.remaining_tokens+c.tokens,updated_at=@now
  FROM dbo.TokenBalances b WITH(UPDLOCK,HOLDLOCK) JOIN @credit c
   ON c.provider=b.model_provider WHERE b.user_id=@user_id;
  INSERT dbo.TokenBalances(user_id,model_provider,remaining_tokens,updated_at)
  SELECT @user_id,c.provider,c.tokens,@now FROM @credit c
  WHERE NOT EXISTS(SELECT 1 FROM dbo.TokenBalances b WITH(UPDLOCK,HOLDLOCK)
    WHERE b.user_id=@user_id AND b.model_provider=c.provider);
  UPDATE dbo.Orders SET status='paid',paid_at=@now
  WHERE order_id=@order_id AND status='pending';
  IF @@ROWCOUNT<>1 THROW 53128,'Order was finalized concurrently',1;
  -- Issue one immutable token lot per paid order detail (snapshot amount).
  INSERT dbo.OrderTokenLots(detail_id,credited_at,issued_tokens,consumed_tokens,refunded_tokens)
  SELECT d.detail_id,@now,d.total_tokens,0,0
  FROM dbo.OrderDetails d WHERE d.order_id=@order_id;
  IF @@ROWCOUNT<>(SELECT COUNT(*) FROM dbo.OrderDetails WHERE order_id=@order_id)
   THROW 54102,'Not every paid detail received an immutable token lot',1;
  COMMIT;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  SET @app_result_id=@order_id;
  IF @emit_result=1 SELECT @order_id AS order_id,@now AS paid_at;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  THROW;
 END CATCH;
END;
GO

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
 IF DB_NAME()<>'$(DatabaseName)'
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
  SET @app_result_id=@task_id;
  IF @emit_result=1 SELECT @task_id AS task_id,@account_id AS account_id,
         @actual_amount AS added_quota,@now AS completed_at;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  THROW;
 END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_W6_RequestRefund
 @order_id INT,
 @emit_result BIT=1,
 @app_result_id INT=NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'$(DatabaseName)'
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
   SET @app_result_id=@order_id;
   IF @emit_result=1 SELECT order_id,refund_id,refund_amount,refundable_tokens,
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
  SET @app_result_id=@order_id;
  IF @emit_result=1 SELECT order_id,refund_id,refund_amount,refundable_tokens,consumed_tokens,
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

CREATE OR ALTER PROCEDURE dbo.usp_W6_AttestRefundPayout
 @order_id INT,
 @external_payout_ref VARCHAR(120),
 @confirmed_employee_id INT,
 @emit_result BIT=1,
 @app_result_id INT=NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'$(DatabaseName)'
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
   SET @app_result_id=@order_id;
   IF @emit_result=1 SELECT order_id,refund_amount,payout_state,external_payout_ref
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
  SET @app_result_id=@order_id;
  IF @emit_result=1 SELECT order_id,refund_amount,payout_state,external_payout_ref
    FROM dbo.RefundLedger WHERE order_id=@order_id;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  THROW;
 END CATCH;
END;
GO
