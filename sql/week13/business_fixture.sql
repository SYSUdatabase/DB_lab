-- 只在一次性专用库执行；此脚本提交夹具供两个连接共享。
IF DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]WebW13%' OR SCHEMA_ID('w13lab') IS NULL
 THROW 57110,'Use a dedicated initialized WebW13 batch',1;
IF OBJECT_ID('w13lab.Business','U') IS NOT NULL
 THROW 57111,'Business fixtures already exist; use a new batch',1;
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRAN;
DECLARE @available bigint,@unit int,@product int,@account int,@employee int,@task int,
 @u1 int,@u2 int,@o1 int,@o2 int,@token int=91703;
SELECT @available=available_quota-outstanding_upstream FROM w11.fn_ProviderSellable('Other');
IF @available<0 OR @available>20000000000 THROW 57112,'Unexpected Other baseline',1;
SET @unit=CONVERT(int,@available/10+1);
WHILE EXISTS(SELECT 1 FROM dbo.Products WHERE model_provider='Other' AND token_amount=@token)
 SET @token+=1;
INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status)
 VALUES(N'W13 Product P',N'Concurrency fixture',1,'Other',@token,@unit,'active');
SET @product=SCOPE_IDENTITY();
INSERT dbo.Users(username,password_hash,email,status)
 VALUES('w13_order_a',REPLICATE('x',60),'w13a@example.invalid','active');
SET @u1=SCOPE_IDENTITY();
INSERT dbo.Users(username,password_hash,email,status)
 VALUES('w13_order_b',REPLICATE('x',60),'w13b@example.invalid','active');
SET @u2=SCOPE_IDENTITY();
INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,safety_threshold,status,expires_at)
 VALUES('Other',N'W13 Fixture',CONVERT(varchar(36),NEWID()),CONVERT(bigint,@unit)*10-@available,0,'active',DATEADD(day,7,SYSDATETIME()));
SET @account=SCOPE_IDENTITY();
SELECT @employee=employee_id FROM dbo.Employees WHERE account='web_admin';
INSERT dbo.RestockTask(account_id,trigger_reason,restock_method,target_amount,status,created_by,assigned_to)
 VALUES(@account,'manual','manual_purchase',5,'pending',@employee,@employee);
SET @task=SCOPE_IDENTITY();
EXEC dbo.usp_W5_CreateRegisteredOrder @u1,0,@o1 OUTPUT;
EXEC dbo.usp_W5_CreateRegisteredOrder @u2,0,@o2 OUTPUT;
EXEC dbo.usp_W5_AddMergedOrderItem @o1,@product,6,0;
EXEC dbo.usp_W5_AddMergedOrderItem @o2,@product,6,0;
IF NOT EXISTS(SELECT 1 FROM w11.fn_ProviderSellable('Other')
 WHERE available_quota-outstanding_upstream=CONVERT(bigint,@unit)*10)
 THROW 57113,'Expected exactly ten sellable packs',1;
CREATE TABLE w13lab.Business(product_id int, units_per_pack int, token_per_pack int,
 account_id int, task_id int, order_a int, order_b int);
INSERT w13lab.Business VALUES(@product,@unit,@token,@account,@task,@o1,@o2);
COMMIT;
SELECT * FROM w13lab.Business;
