-- v1.1 continued: close high-risk direct writes and add atomic payment.
-- Apply only after historical synthetic reconciliation and typed usage links.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME()<>N'TokenHubDB_v11_Issues_20261014'
 THROW 53100,'Wrong v1.1 sandbox; installation refused',1;
IF OBJECT_ID('dbo.trg_W6_InventoryTypedRefs','TR') IS NULL
 OR OBJECT_ID('dbo.trg_W6_ProtectConsumptionReferences','TR') IS NULL
 OR OBJECT_ID('dbo.trg_W6_UsersHistory','TR') IS NOT NULL
 OR OBJECT_ID('dbo.usp_W6_PayPendingOrder','P') IS NOT NULL
 THROW 53101,'Prerequisites absent or write-path hardening already applied',1;
IF EXISTS(SELECT 1 FROM dbo.Orders o JOIN dbo.Users u ON u.user_id=o.user_id
 WHERE o.created_at<u.created_at)
 OR EXISTS(SELECT 1 FROM dbo.TokenUsageLogs t
 JOIN dbo.Users u ON u.user_id=t.user_id WHERE t.used_at<u.created_at)
 OR EXISTS(SELECT 1 FROM dbo.TokenUsageLogs t
 JOIN dbo.Products p ON p.product_id=t.product_id
 JOIN dbo.UpstreamAccount a ON a.account_id=t.account_id
 WHERE t.used_at<a.created_at OR (a.expires_at IS NOT NULL AND t.used_at>=a.expires_at)
 OR p.model_provider<>a.provider)
 THROW 53102,'Existing historical contradictions must be reconciled first',1;
GO
BEGIN TRANSACTION;
GO
CREATE TRIGGER dbo.trg_W6_UsersHistory ON dbo.Users AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted u JOIN dbo.Orders o ON o.user_id=u.user_id
   WHERE o.created_at<u.created_at)
 OR EXISTS(SELECT 1 FROM inserted u JOIN dbo.TokenUsageLogs l ON l.user_id=u.user_id
   WHERE l.used_at<u.created_at)
 THROW 53110,'Cannot change registration date to invalidate existing orders or usage',1;
END;
GO
CREATE TRIGGER dbo.trg_W6_ProductsHistory ON dbo.Products AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.product_id=i.product_id
   WHERE i.model_provider<>d.model_provider
     AND (EXISTS(SELECT 1 FROM dbo.OrderDetails x WHERE x.product_id=i.product_id)
       OR EXISTS(SELECT 1 FROM dbo.TokenUsageLogs x WHERE x.product_id=i.product_id)
       OR EXISTS(SELECT 1 FROM dbo.UsageSummaryCore x WHERE x.product_id=i.product_id)))
 THROW 53111,'Referenced product provider cannot change retroactively',1;
END;
GO
CREATE TRIGGER dbo.trg_W6_AccountHistory ON dbo.UpstreamAccount AFTER UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted a JOIN dbo.TokenUsageLogs l
   ON l.account_id=a.account_id JOIN dbo.Products p ON p.product_id=l.product_id
   WHERE l.used_at<a.created_at
      OR (a.expires_at IS NOT NULL AND l.used_at>=a.expires_at)
      OR a.provider<>p.model_provider)
 THROW 53112,'Account metadata would invalidate historical usage',1;
 IF USER_NAME()<>'dbo' AND (UPDATE(total_quota) OR UPDATE(used_quota))
 THROW 53113,'Direct quota changes are forbidden; use an owner-controlled transaction',1;
END;
GO
CREATE TRIGGER dbo.trg_W6_OrdersHistory ON dbo.Orders AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted o JOIN dbo.Users u ON u.user_id=o.user_id
   WHERE o.created_at<u.created_at)
 THROW 53114,'Order may not precede user registration',1;
 IF USER_NAME()<>'dbo' AND EXISTS(
  SELECT 1 FROM inserted i JOIN deleted d ON d.order_id=i.order_id
  WHERE i.status IN ('paid','refunded') OR d.status IN ('paid','refunded')
      OR i.user_id<>d.user_id OR i.created_at<>d.created_at
 )
 THROW 53115,'Direct finalization or historical order identity changes forbidden',1;
END;
GO
CREATE TRIGGER dbo.trg_W6_InventoryWrite ON dbo.Inventory AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF USER_NAME()<>'dbo'
 THROW 53116,'Inventory changes require an owner-controlled transaction',1;
END;
GO
CREATE TRIGGER dbo.trg_W6_BalanceWrite ON dbo.TokenBalances
AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF USER_NAME()<>'dbo'
 THROW 53117,'Balance changes require an owner-controlled transaction',1;
END;
GO
CREATE TRIGGER dbo.trg_W6_SummaryWrite ON dbo.UsageSummaryCore
AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF USER_NAME()<>'dbo'
 THROW 53118,'Usage summary changes require an owner-controlled transaction',1;
END;
GO
CREATE TRIGGER dbo.trg_W6_DetailsWrite ON dbo.OrderDetails
AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF USER_NAME()<>'dbo'
 THROW 53119,'Use controlled order item procedure for detail changes',1;
END;
GO
CREATE TRIGGER dbo.trg_W6_InventoryLogWrite ON dbo.InventoryLog
AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted)
 THROW 53120,'Inventory movement logs are append-only',1;
 IF USER_NAME()<>'dbo'
 THROW 53121,'Inventory movement must be appended through an owner-controlled procedure',1;
END;
GO
CREATE PROCEDURE dbo.usp_W6_PayPendingOrder
 @order_id INT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
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
  COMMIT;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  SELECT @order_id AS order_id,@now AS paid_at;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  THROW;
 END CATCH;
END;
GO
GRANT EXECUTE ON dbo.usp_W6_PayPendingOrder TO hub_manager;
IF (SELECT COUNT(*) FROM sys.triggers WHERE name LIKE 'trg_W6_%' AND is_disabled=0)<>11
 THROW 53129,'Unexpected v1.1 hardening trigger inventory',1;
COMMIT TRANSACTION;
PRINT 'PASS protected metadata and managed balance/ledger/summary writes; atomic payment installed';
GO
