:on error exit
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
IF OBJECT_ID('w10.fn_OrderDiscount') IS NULL THROW 56999,'Week10 discount function missing',1;
IF (SELECT discount_amount FROM w10.fn_OrderDiscount(99.99))<>0 THROW 56999,'99.99 boundary',1;
IF (SELECT discount_amount FROM w10.fn_OrderDiscount(100))<>5 THROW 56999,'100 boundary',1;
IF (SELECT discount_amount FROM w10.fn_OrderDiscount(499.99))<>25 THROW 56999,'499.99 rounding',1;
IF (SELECT discount_amount FROM w10.fn_OrderDiscount(500))<>50 THROW 56999,'500 boundary',1;
IF EXISTS(SELECT 1 FROM w10.fn_OrderDiscount(NULL)) OR EXISTS(SELECT 1 FROM w10.fn_OrderDiscount(-1)) THROW 56999,'Invalid discount input',1;
IF EXISTS(SELECT 1 FROM w10.fn_SalesSummary(NULL,NULL)) OR EXISTS(SELECT 1 FROM w10.fn_SalesSummary('20260102','20260101')) THROW 56999,'Invalid TVF dates',1;
IF w10.fn_ReplenishmentQuantity(-1,-1,0,100) IS NOT NULL THROW 56999,'Missing inventory must return null',1;
IF EXISTS(SELECT 1 FROM sys.triggers WHERE object_id=OBJECT_ID('dbo.trg_W5_NoEditFinalizedDetails') AND is_disabled=1) THROW 56999,'Finalized guard disabled',1;
IF EXISTS(SELECT 1 FROM sys.check_constraints WHERE parent_object_id IN(OBJECT_ID('dbo.OrderDetails'),OBJECT_ID('w10.InventoryAdjustments')) AND (is_disabled=1 OR is_not_trusted=1)) THROW 56999,'Untrusted checks',1;
EXEC w10.usp_SalesStatistics '99991231','99991231';
DECLARE @empty_report NVARCHAR(MAX);
EXEC w10.usp_SalesStatistics '99991231','99991231',@emit_result=0,@app_data=@empty_report OUTPUT;
IF COALESCE(JSON_QUERY(@empty_report,'$.items'),N'missing')<>N'[]'
 OR COALESCE(JSON_VALUE(@empty_report,'$.summary.order_count'),N'missing')<>N'0'
 THROW 56999,'Empty report must preserve zero summary and items array',1;
PRINT 'PASS week10 SQL function, schema and maximum-date assertions';
GO
-- Positive workflow fixtures roll back every row after assertions.
BEGIN TRANSACTION;
DECLARE @suffix VARCHAR(32)=REPLACE(CONVERT(VARCHAR(36),NEWID()),'-',''),
 @user INT,@p INT,@q INT,@one INT,@two INT,@detail INT,@admin INT,@account INT,
 @key UNIQUEIDENTIFIER=NEWID(),@adjustment BIGINT,@repeat BIGINT,@json NVARCHAR(MAX),@today DATE=CONVERT(DATE,SYSDATETIME());
INSERT dbo.Users(username,password_hash,email) VALUES(CONCAT('w10_',@suffix),'UNUSABLE-TEST-FIXTURE',CONCAT(@suffix,'@week10.invalid'));
SET @user=CONVERT(INT,SCOPE_IDENTITY());
INSERT dbo.Products(name,price,model_provider,token_amount,required_upstream_tokens)
 VALUES(CONCAT('w10_P_',@suffix),30,'Other',2000000001,1);
SET @p=CONVERT(INT,SCOPE_IDENTITY());
INSERT dbo.Products(name,price,model_provider,token_amount,required_upstream_tokens)
 VALUES(CONCAT('w10_Q_',@suffix),40,'Other',2000000002,1);
SET @q=CONVERT(INT,SCOPE_IDENTITY());
EXEC dbo.usp_W5_CreateRegisteredOrder @user,@emit_result=0,@app_result_id=@one OUTPUT;
EXEC dbo.usp_W5_AddMergedOrderItem @one,@p,2,@emit_result=0;
EXEC dbo.usp_W5_AddMergedOrderItem @one,@q,1,@emit_result=0;
IF (SELECT total_amount FROM dbo.Orders WHERE order_id=@one)<>95 THROW 56999,'Multi-item order discount',1;
EXEC dbo.usp_W6_PayPendingOrder @one,@emit_result=0;
EXEC dbo.usp_W5_CreateRegisteredOrder @user,@emit_result=0,@app_result_id=@two OUTPUT;
EXEC dbo.usp_W5_AddMergedOrderItem @two,@p,1,@emit_result=0;
EXEC dbo.usp_W6_PayPendingOrder @two,@emit_result=0;
IF NOT EXISTS(SELECT 1 FROM w10.fn_SalesSummary(@today,@today) WHERE product_id=@p AND sales_quantity=3 AND sales_amount=87 AND order_count=2)
 THROW 56999,'Product sales aggregation',1;
IF NOT EXISTS(SELECT 1 FROM w10.fn_SalesSummary(@today,@today) WHERE product_id=@q AND sales_quantity=1 AND sales_amount=38 AND order_count=1)
 THROW 56999,'Second product aggregation',1;
EXEC dbo.usp_W6_RequestRefund @one,@emit_result=0;
IF NOT EXISTS(SELECT 1 FROM w10.fn_SalesSummary(@today,@today) WHERE product_id=@p AND sales_amount=87)
 THROW 56999,'Refunded sales must retain original paid amount',1;
SELECT TOP(1) @admin=e.employee_id FROM dbo.Employees e JOIN dbo.Roles r ON r.role_id=e.role_id WHERE e.status='active' AND r.role_name='admin' ORDER BY employee_id;
IF @admin IS NULL THROW 56999,'Administrator fixture required',1;
INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,used_quota,safety_threshold)
 VALUES('Other',CONCAT('w10_',@suffix),'SIMULATION-NO-EXTERNAL-KEY',1200,200,200);
SET @account=CONVERT(INT,SCOPE_IDENTITY());
EXEC w10.usp_AdjustInventory @p,@account,300,N'positive fixture',@admin,@key,@emit_result=0,@app_result_id=@adjustment OUTPUT;
EXEC w10.usp_AdjustInventory @p,@account,300,N'positive fixture',@admin,@key,@emit_result=0,@app_result_id=@repeat OUTPUT;
IF @adjustment<>@repeat OR (SELECT COUNT(*) FROM w10.InventoryAdjustments WHERE operation_key=@key)<>1 THROW 56999,'Idempotent adjustment replay',1;
SET @key=NEWID();
EXEC w10.usp_AdjustInventory @p,@account,-400,N'negative fixture',@admin,@key,@emit_result=0;
IF NOT EXISTS(SELECT 1 FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON a.account_id=i.account_id
 WHERE a.account_id=@account AND total_quota=1100 AND used_quota=200 AND current_quota=900)
 THROW 56999,'Positive/negative adjustment accounting',1;
IF w10.fn_ReplenishmentQuantity(@p,@account,1000,2000)<>1100 THROW 56999,'Replenishment calculation',1;
IF w10.fn_ReplenishmentQuantity(@p,@account,NULL,2000)<>0 THROW 56999,'Default minimum uses safety threshold',1;
IF (SELECT SUM(change_amount) FROM dbo.InventoryLog WHERE account_id=@account AND change_type='adjustment')<>-100
 THROW 56999,'Adjustment movement sum',1;
ROLLBACK TRANSACTION;
PRINT 'PASS week10 discounted sales, refund, audited adjustment replay and inventory assertions';
GO
BEGIN TRY
 EXEC w10.usp_SalesStatistics NULL,'20260101';
 THROW 56999,'Null date unexpectedly accepted',1;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER()<>56000 THROW;
END CATCH;
BEGIN TRY
 EXEC w10.usp_SalesStatistics '20260102','20260101';
 THROW 56999,'Reversed dates unexpectedly accepted',1;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER()<>56000 THROW;
END CATCH;
BEGIN TRY
 EXEC w10.usp_AdjustInventory -1,-1,0,N'',-1,NULL;
 THROW 56999,'Invalid adjustment unexpectedly accepted',1;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER()<>56000 THROW;
END CATCH;
PRINT 'PASS week10 expected business errors';
GO
