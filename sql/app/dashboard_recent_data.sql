-- Parameterized by tools/seed_dashboard_recent.py; no runtime role grants.
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON;
SET ANSI_PADDING ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]Web%'
 THROW 55810,'Recent samples require a v11 Web database',1;
IF OBJECT_ID('app.Dashboard','P') IS NULL OR OBJECT_ID('dbo.usp_W6_RequestRefund','P') IS NULL
 THROW 55810,'Install the Web application and dashboard first',1;
IF IS_SRVROLEMEMBER('sysadmin')<>1 AND IS_MEMBER('db_owner')<>1
 THROW 55811,'Run sample preparation with the database setup identity',1;
DECLARE @password_hash VARCHAR(60)=?,@today DATE=CONVERT(DATE,SYSDATETIME()),
 @now DATETIME2(0)=SYSDATETIME(),@user INT,@product INT,@tokens INT=194014,
 @day DATE,@offset INT=13,@slot INT,@count INT,@order INT,@created DATETIME2(0),
 @inserted INT=0,@lock_result INT,@email VARCHAR(100),@description NVARCHAR(MAX);
BEGIN TRY
 BEGIN TRANSACTION;
 EXEC @lock_result=sys.sp_getapplock @Resource=N'dashboard.recent.samples.v1',
  @LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @lock_result<0 THROW 55812,'Another recent sample preparation is running',1;
 SELECT @user=user_id,@email=email FROM dbo.Users WITH(UPDLOCK,HOLDLOCK)
  WHERE username='dashboard_recent_sample';
 IF @user IS NULL
 BEGIN
  INSERT dbo.Users(username,password_hash,email,created_at,updated_at)
   VALUES('dashboard_recent_sample',@password_hash,'dashboard_recent_sample@sample.invalid',DATEADD(DAY,-14,@today),@now);
  SET @user=CONVERT(INT,SCOPE_IDENTITY());
 END
 ELSE IF @email<>'dashboard_recent_sample@sample.invalid'
  OR NOT EXISTS(SELECT 1 FROM dbo.Users WHERE user_id=@user AND status='active' AND created_at<=DATEADD(DAY,-13,@today))
  THROW 55813,'Reserved sample user conflicts with existing data',1;
 SELECT @product=product_id,@description=description FROM dbo.Products WITH(UPDLOCK,HOLDLOCK)
  WHERE name=N'Dashboard Recent Sample';
 IF @product IS NULL
 BEGIN
  WHILE EXISTS(SELECT 1 FROM dbo.Products WHERE model_provider='Other' AND token_amount=@tokens)
   SET @tokens=@tokens+1;
  INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status,created_at)
   VALUES(N'Dashboard Recent Sample',N'DASHBOARD_RECENT_SAMPLE_V1',12.50,'Other',@tokens,100,'active',DATEADD(DAY,-14,@today));
  SET @product=CONVERT(INT,SCOPE_IDENTITY());
 END
 ELSE IF @description IS NULL OR @description<>N'DASHBOARD_RECENT_SAMPLE_V1'
  THROW 55813,'Reserved sample product conflicts with existing data',1;
 WHILE @offset>=0
 BEGIN
  SET @day=DATEADD(DAY,-@offset,@today);
  SET @count=DATEDIFF(DAY,CONVERT(DATE,'20000101'),@day)%4+1;
  SET @slot=0;
  WHILE @slot<@count
  BEGIN
   SET @created=DATEADD(SECOND,@slot,CONVERT(DATETIME2(0),@day));
   IF @created<=@now AND NOT EXISTS(
    SELECT 1 FROM dbo.Orders WITH(UPDLOCK,HOLDLOCK) WHERE user_id=@user AND created_at=@created)
   BEGIN
    INSERT dbo.Orders(user_id,total_amount,total_tokens,status,created_at)
     VALUES(@user,0,0,'pending',@created);
    SET @order=CONVERT(INT,SCOPE_IDENTITY());
    DECLARE @quantity INT=(@offset+@slot)%3+1,@kind INT=(@offset+@slot)%4;
    EXEC dbo.usp_W5_AddMergedOrderItem @order,@product,@quantity,@emit_result=0;
    IF @kind IN(1,3)
     EXEC dbo.usp_W6_PayPendingOrder @order,@emit_result=0;
    IF @kind=2 UPDATE dbo.Orders SET status='cancelled' WHERE order_id=@order;
    IF @kind=3 EXEC dbo.usp_W6_RequestRefund @order,@emit_result=0;
    SET @inserted=@inserted+1;
   END;
   SET @slot=@slot+1;
  END;
  SET @offset=@offset-1;
 END;
 DECLARE @result NVARCHAR(MAX)=(SELECT @inserted inserted_orders,'dashboard_recent_sample' sample_user,
  CONVERT(CHAR(10),DATEADD(DAY,-13,@today),23) start_date,CONVERT(CHAR(10),@today,23) end_date,
  JSON_QUERY((SELECT CONVERT(CHAR(10),created_at,23) [day],COUNT(*) order_count FROM dbo.Orders
   WHERE user_id=@user AND created_at>=DATEADD(DAY,-13,@today) AND created_at<DATEADD(DAY,1,@today)
   GROUP BY CONVERT(CHAR(10),created_at,23) ORDER BY [day] FOR JSON PATH)) daily_orders
  FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 COMMIT TRANSACTION;
 SELECT @result data;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
