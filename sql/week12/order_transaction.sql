-- 第12周订单完成事务。由 install.sql 安装；调用示例与提交、回滚验证见 test_transactions.sql。
--
-- 口径：本项目以 paid 为“已完成”。完成时把订单 Token 按供应商记入顾客余额并逐明细发放
-- Token 批次；上游账号库存仍在顾客模拟调用时按实际用量扣减（第10周及以前的扣减时机不变），
-- 因此完成事务不扣上游库存，而是先按“份数×每份上游消耗”核对可售余量（w11.fn_ProviderSellable）防止超卖。
-- 一张订单只能完成一次：状态条件更新 WHERE status='pending' 并检查受影响行数，
-- 已完成的订单返回 53131，不会第二次记入余额。
--
-- 事务边界与调用关系：
--   Web  app.[Execute] 'orders.pay'  （外层事务，入口统一提交或回滚）
--     └─ dbo.usp_W6_PayPendingOrder  （保留原名的薄封装，供原有调用方使用）
--          └─ w12.usp_CompleteOrder   （本过程：检查、记余额、改状态、发批次）
--               └─ UPDATE dbo.Orders 触发 dbo.trg_W11_OrderCompletionRules 等触发器，
--                  在同一事务内再次核对明细、金额与可售余量；任一步出错整体回滚。
-- 测试时可用会话上下文 w12.fail_point='order_after_credit'，在余额已记入、状态未改之前
-- 主动抛错，验证回滚。
CREATE PROCEDURE w12.usp_CompleteOrder
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
         @user_id INT,@status VARCHAR(24),@amount DECIMAL(10,2),@total BIGINT,@created DATETIME2(0);
 BEGIN TRY
  SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  BEGIN TRANSACTION;
  SELECT @user_id=o.user_id,@status=o.status,@amount=o.total_amount,@total=o.total_tokens,@created=o.created_at
  FROM dbo.Orders o WITH(UPDLOCK,HOLDLOCK) WHERE o.order_id=@order_id;
  IF @status IS NULL
   THROW 53123,'Order does not exist',1;
  IF @status IN ('paid','refunded','partially_refunded')
   THROW 53131,'Order is already completed; tokens were credited once and are not credited again',1;
  IF @status<>'pending' OR @created>@now
   THROW 53123,'Only a pending order can be completed',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Users u
    WHERE u.user_id=@user_id AND u.status='active' AND u.created_at<=@now)
   THROW 53124,'Registered active buyer required',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.OrderDetails WITH(UPDLOCK,HOLDLOCK) WHERE order_id=@order_id)
   THROW 53125,'Cannot complete an order without details',1;
  IF EXISTS(SELECT 1 FROM dbo.OrderDetails d LEFT JOIN dbo.Products p ON p.product_id=d.product_id
     WHERE d.order_id=@order_id AND (p.product_id IS NULL
      OR p.model_provider NOT IN ('OpenAI','Claude','Gemini','Other') OR d.quantity<=0))
   THROW 53126,'Order detail has no creditable product or a non-positive quantity',1;
  IF (SELECT SUM(d.subtotal) FROM dbo.OrderDetails d WHERE d.order_id=@order_id)<>@amount
    OR (SELECT SUM(d.total_tokens) FROM dbo.OrderDetails d WHERE d.order_id=@order_id)<>@total
   THROW 53127,'Order amounts do not match detail snapshots',1;
  DECLARE @version VARCHAR(32),@gross DECIMAL(18,2),@rate DECIMAL(5,4);
  SELECT @version=pricing_rule_version FROM dbo.Orders WHERE order_id=@order_id;
  SELECT @gross=SUM(CONVERT(DECIMAL(18,2),original_subtotal)) FROM dbo.OrderDetails WHERE order_id=@order_id;
  SELECT @rate=CASE WHEN @version='legacy' THEN 0 ELSE discount_rate END FROM w10.fn_OrderDiscount(@gross);
  IF @rate IS NULL OR EXISTS(SELECT 1 FROM dbo.OrderDetails WHERE order_id=@order_id AND
   (pricing_rule_version<>@version OR discount_rate<>@rate
    OR original_subtotal<>CONVERT(DECIMAL(18,2),quantity)*unit_price
    OR discount_amount<>CONVERT(DECIMAL(10,2),ROUND(original_subtotal*@rate,2))
    OR subtotal<>original_subtotal-discount_amount OR total_tokens<>CONVERT(BIGINT,quantity)*tokens_per_unit))
   THROW 56009,'Pricing snapshots do not match the order rule',1;
  -- 按商品汇总需求量（份数、顾客 Token、上游消耗），再按供应商汇总：Token 记入余额，上游消耗核对可售余量。
  DECLARE @need TABLE(product_id INT PRIMARY KEY, provider VARCHAR(50) NOT NULL, quantity BIGINT NOT NULL,
   tokens BIGINT NOT NULL, upstream DECIMAL(38,0) NOT NULL);
  INSERT @need SELECT d.product_id,p.model_provider,SUM(CONVERT(BIGINT,d.quantity)),SUM(d.total_tokens),
   SUM(CONVERT(DECIMAL(38,0),d.quantity)*p.required_upstream_tokens)
  FROM dbo.OrderDetails d JOIN dbo.Products p ON p.product_id=d.product_id
  WHERE d.order_id=@order_id GROUP BY d.product_id,p.model_provider;
  DECLARE @credit TABLE (provider VARCHAR(50) PRIMARY KEY, tokens BIGINT NOT NULL);
  INSERT @credit SELECT provider,SUM(tokens) FROM @need GROUP BY provider;
  -- 加锁顺序与模拟调用一致：先锁本顾客的余额行，再在 SERIALIZABLE 下读取账号与库存，
  -- 读到的范围保持共享锁直到提交，核对之后库存不会被并发调用改小。
  DECLARE @locked INT;
  SELECT @locked=COUNT(*) FROM dbo.TokenBalances WITH(UPDLOCK,HOLDLOCK)
  WHERE user_id=@user_id AND model_provider IN (SELECT provider FROM @credit);
  IF EXISTS(SELECT 1 FROM (SELECT provider,SUM(upstream) upstream FROM @need GROUP BY provider) n
    CROSS APPLY w11.fn_ProviderSellable(n.provider) s WHERE n.upstream>s.available_quota-s.outstanding_upstream)
   THROW 53132,'Insufficient sellable upstream inventory for this order',1;
  UPDATE b SET remaining_tokens=b.remaining_tokens+c.tokens,updated_at=@now
  FROM dbo.TokenBalances b WITH(UPDLOCK,HOLDLOCK) JOIN @credit c
   ON c.provider=b.model_provider WHERE b.user_id=@user_id;
  INSERT dbo.TokenBalances(user_id,model_provider,remaining_tokens,updated_at)
  SELECT @user_id,c.provider,c.tokens,@now FROM @credit c
  WHERE NOT EXISTS(SELECT 1 FROM dbo.TokenBalances b WITH(UPDLOCK,HOLDLOCK)
    WHERE b.user_id=@user_id AND b.model_provider=c.provider);
  IF CONVERT(NVARCHAR(40),SESSION_CONTEXT(N'w12.fail_point'))=N'order_after_credit'
   THROW 54490,'Injected failure after crediting balances and before completing the order',1;
  UPDATE dbo.Orders SET status='paid',paid_at=@now
  WHERE order_id=@order_id AND status='pending';
  IF @@ROWCOUNT<>1 THROW 53128,'Order was finalized concurrently',1;
  INSERT dbo.OrderTokenLots(detail_id,credited_at,issued_tokens,consumed_tokens,refunded_tokens)
  SELECT d.detail_id,@now,d.total_tokens,0,0
  FROM dbo.OrderDetails d WHERE d.order_id=@order_id;
  IF @@ROWCOUNT<>(SELECT COUNT(*) FROM dbo.OrderDetails WHERE order_id=@order_id)
   THROW 54102,'Not every paid detail received an immutable token lot',1;
  COMMIT TRANSACTION;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  SET @app_result_id=@order_id;
  IF @emit_result=1
   SELECT @order_id AS order_id,'paid' AS status,@now AS paid_at,@amount AS total_amount,@total AS credited_tokens;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  THROW;
 END CATCH;
END;
GO
-- 原支付过程改为调用新事务，Web 的“模拟支付”与 SQL 直接调用走同一实现。
CREATE OR ALTER PROCEDURE dbo.usp_W6_PayPendingOrder
 @order_id INT,
 @emit_result BIT=1,
 @app_result_id INT=NULL OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 EXEC w12.usp_CompleteOrder @order_id,@emit_result=@emit_result,@app_result_id=@app_result_id OUTPUT;
END;
GO
