SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE PROCEDURE w10.usp_SalesStatistics @start_date DATE,@end_date DATE,
 @emit_result BIT=1,@app_data NVARCHAR(MAX)=NULL OUTPUT
WITH EXECUTE AS OWNER AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_NULLS ON;
 SET ANSI_WARNINGS ON;
 SET ANSI_PADDING ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 IF @start_date IS NULL OR @end_date IS NULL OR @start_date>@end_date THROW 56000,'Valid ordered dates required',1;
 -- One materialized read supplies both result sets and the app JSON.
 SELECT o.order_id,p.product_id,p.name name,CONVERT(BIGINT,d.quantity) quantity,
 CONVERT(DECIMAL(38,2),d.subtotal) amount INTO #sales
 FROM dbo.Orders o JOIN dbo.OrderDetails d ON d.order_id=o.order_id
 JOIN dbo.Products p ON p.product_id=d.product_id
 WHERE o.status IN('paid','refunded','partially_refunded') AND o.paid_at>=CONVERT(DATETIME2(0),@start_date)
 AND (@end_date='99991231' OR o.paid_at<DATEADD(DAY,1,CONVERT(DATETIME2(0),NULLIF(@end_date,CONVERT(DATE,'99991231')))));
 SELECT COUNT_BIG(DISTINCT order_id) order_count,COALESCE(SUM(quantity),CONVERT(BIGINT,0)) sales_quantity,
 COALESCE(SUM(amount),CONVERT(DECIMAL(38,2),0)) sales_amount INTO #summary FROM #sales;
 SELECT product_id,name,SUM(quantity) sales_quantity,SUM(amount) sales_amount,
 COUNT_BIG(DISTINCT order_id) order_count INTO #items FROM #sales GROUP BY product_id,name;
 SET @app_data=(SELECT JSON_QUERY((SELECT * FROM #summary FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)) summary,
 JSON_QUERY(COALESCE((SELECT * FROM #items ORDER BY product_id FOR JSON PATH),N'[]')) items FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 IF @emit_result=1
 BEGIN
  SELECT * FROM #summary;
  SELECT * FROM #items ORDER BY product_id;
 END;
END;
GO
CREATE PROCEDURE w10.usp_AdjustInventory
 @product_id INT,@account_id INT,@change_amount BIGINT,@reason NVARCHAR(MAX),
 @operator_id INT,@operation_key UNIQUEIDENTIFIER,@emit_result BIT=1,@app_result_id BIGINT=NULL OUTPUT
WITH EXECUTE AS OWNER AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_NULLS ON;
 SET ANSI_WARNINGS ON;
 SET ANSI_PADDING ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 SET XACT_ABORT ON;
 IF @product_id IS NULL OR @product_id<=0 OR @account_id IS NULL OR @account_id<=0
 OR @change_amount IS NULL OR @change_amount=0 OR @operation_key IS NULL
 OR @reason IS NULL OR LEN(TRIM(@reason))=0 OR DATALENGTH(@reason)>510
 THROW 56000,'Valid product, account, nonzero quantity, reason and operation key required',1;
 DECLARE @provider VARCHAR(50),@account_provider VARCHAR(50),@current BIGINT,@total BIGINT,@used BIGINT,
 @status VARCHAR(24),@created DATETIME2(0),@expiry DATETIME2(0),@now DATETIME2(0)=SYSDATETIME(),
 @new_total DECIMAL(20,0),@new_current DECIMAL(20,0),@log INT,@lock_result INT;
 BEGIN TRY
  BEGIN TRANSACTION;
  -- Serialize a key before row locks, including concurrent first-time requests.
  DECLARE @resource NVARCHAR(255)=CONCAT(N'w10.adjustment.',CONVERT(NVARCHAR(36),@operation_key));
  EXEC @lock_result=sys.sp_getapplock @Resource=@resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
  IF @lock_result<0 THROW 56009,'Adjustment key is busy',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Employees e WITH(HOLDLOCK) JOIN dbo.Roles r ON r.role_id=e.role_id
   WHERE e.employee_id=@operator_id AND e.status='active' AND r.role_name='admin')
   THROW 56003,'Active administrator required',1;
  SET @app_result_id=NULL;
  SELECT @app_result_id=adjustment_id FROM w10.InventoryAdjustments WHERE operation_key=@operation_key;
  IF @app_result_id IS NOT NULL
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM w10.InventoryAdjustments WHERE adjustment_id=@app_result_id
    AND product_id=@product_id AND account_id=@account_id AND change_amount=@change_amount
    AND operator_id=@operator_id AND CONVERT(VARBINARY(MAX),reason)=CONVERT(VARBINARY(MAX),@reason))
    THROW 56009,'Operation key already has different parameters',1;
  END
  ELSE
  BEGIN
   SELECT @provider=model_provider FROM dbo.Products WITH(UPDLOCK,HOLDLOCK) WHERE product_id=@product_id;
   SELECT @account_provider=provider,@total=total_quota,@used=used_quota,@status=status,@created=created_at,@expiry=expires_at
    FROM dbo.UpstreamAccount WITH(UPDLOCK,HOLDLOCK) WHERE account_id=@account_id;
   IF @provider IS NULL OR @account_provider IS NULL THROW 56004,'Product or account missing',1;
   IF @provider<>@account_provider THROW 56000,'Product and account providers differ',1;
   IF @status<>'active' OR @created>@now OR (@expiry IS NOT NULL AND @expiry<=@now) THROW 56009,'Account unavailable',1;
   SELECT @current=current_quota FROM dbo.Inventory WITH(UPDLOCK,HOLDLOCK) WHERE account_id=@account_id;
   IF @current IS NULL OR @current<>@total-@used THROW 56009,'Inventory pair is missing or inconsistent',1;
   SET @new_total=CONVERT(DECIMAL(20,0),@total)+CONVERT(DECIMAL(20,0),@change_amount);
   SET @new_current=CONVERT(DECIMAL(20,0),@current)+CONVERT(DECIMAL(20,0),@change_amount);
   IF @new_total<=0 OR @new_total>9223372036854775807 OR @new_current<0
    OR @new_current>9223372036854775807 OR @new_total<@used THROW 56009,'Adjustment exceeds quota bounds',1;
   UPDATE dbo.UpstreamAccount SET total_quota=CONVERT(BIGINT,@new_total),updated_at=@now WHERE account_id=@account_id;
   UPDATE dbo.Inventory SET current_quota=CONVERT(BIGINT,@new_current),last_updated_at=@now WHERE account_id=@account_id;
   INSERT dbo.InventoryLog(account_id,change_type,change_amount,reference_type,reference_id,reason,operator_id,created_at)
    VALUES(@account_id,'adjustment',@change_amount,'manual',NULL,@reason,@operator_id,@now);
   SET @log=CONVERT(INT,SCOPE_IDENTITY());
   INSERT w10.InventoryAdjustments(operation_key,product_id,account_id,operator_id,change_amount,reason,
    before_current_quota,after_current_quota,before_total_quota,after_total_quota,log_id,created_at)
   VALUES(@operation_key,@product_id,@account_id,@operator_id,@change_amount,@reason,
    @current,CONVERT(BIGINT,@new_current),@total,CONVERT(BIGINT,@new_total),@log,@now);
   SET @app_result_id=CONVERT(BIGINT,SCOPE_IDENTITY());
  END;
  COMMIT TRANSACTION;
  IF @emit_result=1 SELECT * FROM w10.InventoryAdjustments WHERE adjustment_id=@app_result_id;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH;
END;
GO
CREATE PROCEDURE w10.usp_RepriceDraft @order_id INT
WITH EXECUTE AS OWNER AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_NULLS ON;
 SET ANSI_WARNINGS ON;
 SET ANSI_PADDING ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 SET XACT_ABORT ON;
 DECLARE @version VARCHAR(32),@gross DECIMAL(18,2),@rate DECIMAL(5,4);
 BEGIN TRY
  BEGIN TRANSACTION;
  SELECT @version=pricing_rule_version FROM dbo.Orders WITH(UPDLOCK,HOLDLOCK) WHERE order_id=@order_id AND status='pending';
  IF @version IS NULL THROW 56009,'Pending order required for repricing',1;
  SELECT @gross=COALESCE(SUM(CONVERT(DECIMAL(18,2),quantity)*unit_price),0)
   FROM dbo.OrderDetails WITH(UPDLOCK,HOLDLOCK) WHERE order_id=@order_id;
  SELECT @rate=CASE WHEN @version='legacy' THEN 0 ELSE discount_rate END FROM w10.fn_OrderDiscount(@gross);
  IF @rate IS NULL THROW 56000,'Invalid gross amount',1;
  UPDATE dbo.OrderDetails SET original_subtotal=CONVERT(DECIMAL(10,2),CONVERT(DECIMAL(18,2),quantity)*unit_price),
   discount_rate=@rate,discount_amount=CONVERT(DECIMAL(10,2),ROUND(CONVERT(DECIMAL(18,2),quantity)*unit_price*@rate,2)),
   subtotal=CONVERT(DECIMAL(10,2),CONVERT(DECIMAL(18,2),quantity)*unit_price-ROUND(CONVERT(DECIMAL(18,2),quantity)*unit_price*@rate,2)),
   pricing_rule_version=@version WHERE order_id=@order_id;
  UPDATE dbo.Orders SET total_amount=(SELECT COALESCE(SUM(subtotal),0) FROM dbo.OrderDetails WHERE order_id=@order_id),
   total_tokens=(SELECT COALESCE(SUM(total_tokens),0) FROM dbo.OrderDetails WHERE order_id=@order_id) WHERE order_id=@order_id;
  COMMIT TRANSACTION;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH;
END;
GO




