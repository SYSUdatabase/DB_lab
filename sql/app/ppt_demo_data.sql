-- Run only through tools/prepare_ppt_demo.py inside its transaction.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON;
SET ANSI_PADDING ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]Web%'
 OR OBJECT_ID(N'app.Dashboard',N'P') IS NULL
 THROW 55820,'Install the Web application and dashboard in a v11 Web database first',1;
IF IS_SRVROLEMEMBER('sysadmin')<>1 AND IS_MEMBER('db_owner')<>1
 THROW 55820,'Use the database setup identity for PPT preparation',1;
DECLARE @hash VARCHAR(60)=?,@user INT,@product INT,@account INT;
IF EXISTS(SELECT 1 FROM dbo.Users WHERE username='li_demo')
 OR EXISTS(SELECT 1 FROM dbo.Employees WHERE account='zhang_staff')
 THROW 55821,'Slide 7 accounts already exist. Use a new README database batch',1;
SELECT @user=user_id FROM dbo.Users WHERE username='chen_demo';
IF @user IS NOT NULL AND (
 EXISTS(SELECT 1 FROM dbo.Orders WHERE user_id=@user)
 OR EXISTS(SELECT 1 FROM dbo.TokenUsageLogs WHERE user_id=@user)
 OR EXISTS(SELECT 1 FROM dbo.TokenBalances WHERE user_id=@user AND remaining_tokens<>0)
 OR NOT EXISTS(SELECT 1 FROM dbo.Users WHERE user_id=@user AND status='active'
   AND email='chen_demo@example.invalid'))
 THROW 55821,'chen_demo has activity or conflicting details. Use a new database batch',1;
IF @user IS NULL
BEGIN
 INSERT dbo.Users(username,email,password_hash)
 VALUES('chen_demo','chen_demo@example.invalid',@hash);
 SET @user=CONVERT(INT,SCOPE_IDENTITY());
END;
UPDATE dbo.Users SET password_hash=@hash WHERE user_id=@user;
DECLARE @admin INT;
SELECT @admin=e.employee_id FROM dbo.Employees e JOIN dbo.Roles r ON r.role_id=e.role_id
 WHERE e.account='web_admin' AND e.status='active' AND r.role_name='admin';
IF @admin IS NULL THROW 55821,'The prepared web_admin administrator is missing',1;
UPDATE dbo.Employees SET password_hash=@hash WHERE employee_id=@admin;
UPDATE app.Sessions SET revoked_at=SYSDATETIME()
 WHERE (user_id=@user OR employee_id=@admin) AND revoked_at IS NULL;
SELECT @product=product_id FROM dbo.Products WHERE name=N'入门体验套餐';
IF @product IS NOT NULL AND NOT EXISTS(
 SELECT 1 FROM dbo.Products WHERE product_id=@product AND model_provider='Other' AND token_amount=100000)
 THROW 55821,'The product name is already used for a different tier',1;
IF @product IS NULL
 SELECT @product=product_id FROM dbo.Products WHERE model_provider='Other' AND token_amount=100000;
IF @product IS NULL
 INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status)
 VALUES(N'入门体验套餐',N'本轮PPT流程使用',6.90,'Other',100000,100000,'active');
ELSE
 UPDATE dbo.Products SET name=N'入门体验套餐',description=N'本轮PPT流程使用',price=6.90,
 required_upstream_tokens=100000,status='active' WHERE product_id=@product;
IF @product IS NULL SET @product=CONVERT(INT,SCOPE_IDENTITY());
SELECT @account=account_id FROM dbo.UpstreamAccount
 WHERE provider='Other' AND account_name=N'展示库存账号';
IF @account IS NULL
BEGIN
 INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,safety_threshold,status,expires_at)
 VALUES('Other',N'展示库存账号',N'SIMULATION-NO-EXTERNAL-KEY',10000,20000,'active',DATEADD(year,1,SYSDATETIME()));
 SET @account=CONVERT(INT,SCOPE_IDENTITY());
END;
IF NOT EXISTS(SELECT 1 FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id
 WHERE a.account_id=@account AND a.total_quota=10000 AND a.used_quota=0
 AND a.status='active' AND a.expires_at>SYSDATETIME() AND a.safety_threshold=20000 AND i.current_quota=10000)
 OR EXISTS(SELECT 1 FROM dbo.RestockTask WHERE account_id=@account)
 THROW 55821,'The walkthrough inventory has changed. Use a new database batch',1;
IF NOT EXISTS(SELECT 1 FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id
 WHERE a.provider='Other' AND a.status='active' AND a.created_at<=SYSDATETIME()
 AND (a.expires_at IS NULL OR a.expires_at>SYSDATETIME()) AND i.current_quota>=20000
 AND a.total_quota-a.used_quota>=20000)
 THROW 55821,'No valid Other account can handle the 20000-token call',1;
SELECT (SELECT 'chen_demo' AS customer,N'入门体验套餐' AS product,N'展示库存账号' AS inventory_account,
 @product AS product_id,@account AS account_id,
 (SELECT COUNT_BIG(*) FROM dbo.Orders) AS total_orders,
 (SELECT COALESCE(SUM(CONVERT(DECIMAL(22,2),total_amount)),0) FROM dbo.Orders
  WHERE status IN('paid','refunded','partially_refunded')) AS gross_paid_amount,
 (SELECT COALESCE(SUM(CONVERT(DECIMAL(22,2),refund_amount)),0) FROM dbo.RefundLedger) AS refund_amount,
 (SELECT COUNT_BIG(*) FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id
  WHERE a.status='active' AND i.current_quota<a.safety_threshold) AS low_stock_accounts,
 CONVERT(VARCHAR(19),SYSDATETIME(),120) AS prepared_at
 FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS data;
