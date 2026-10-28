-- Run against the separately installed v11 Web database only (SQLCMD mode).
:on error exit
USE [$(DatabaseName)];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]Web%' THROW 55000,'Refuse non-Web database',1;
IF SCHEMA_ID(N'app') IS NOT NULL THROW 55009,'app schema already installed',1;
IF OBJECT_ID('dbo.usp_W6_AttestRefundPayout','P') IS NULL
 OR OBJECT_ID('dbo.OrderTokenLots','U') IS NULL THROW 55000,'Complete v11 base required',1;
BEGIN TRANSACTION;
GO
CREATE SCHEMA app AUTHORIZATION dbo;
GO
CREATE ROLE app_runtime AUTHORIZATION dbo;
:r sql/app/opening_inventory.sql
-- SQL Server UNIQUE constraints include NULL, so pending liabilities require a filtered index.
ALTER TABLE dbo.RefundLedger DROP CONSTRAINT UQ_Refund_external_ref;
CREATE UNIQUE INDEX UX_Refund_external_ref ON dbo.RefundLedger(external_payout_ref) WHERE external_payout_ref IS NOT NULL;
GO
CREATE TABLE app.Sessions(
 token_hash BINARY(32) NOT NULL CONSTRAINT PK_app_Sessions PRIMARY KEY,
 user_id INT NULL REFERENCES dbo.Users(user_id),
 employee_id INT NULL REFERENCES dbo.Employees(employee_id),
 expires_at DATETIME2(0) NOT NULL,
 revoked_at DATETIME2(0) NULL,
 CONSTRAINT CK_app_Sessions_identity CHECK(
  (user_id IS NOT NULL AND employee_id IS NULL) OR
  (user_id IS NULL AND employee_id IS NOT NULL))
);
GO
-- The existing child guard needs a controlled exception to delete an unused pair.
-- A caller cannot exploit the flag: only the owner execution context may use it.
CREATE OR ALTER TRIGGER dbo.trg_W5_PreventInventoryDetach
ON dbo.Inventory AFTER UPDATE,DELETE AS
BEGIN
 SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
 IF USER_NAME()='dbo' AND TRY_CONVERT(INT,SESSION_CONTEXT(N'app_account_delete'))=1 AND @@TRANCOUNT>0 RETURN;
 IF EXISTS(SELECT 1 FROM deleted d JOIN dbo.UpstreamAccount a ON a.account_id=d.account_id
  WHERE NOT EXISTS(SELECT 1 FROM dbo.Inventory v WHERE v.account_id=a.account_id))
  THROW 52108,'Inventory row is required for every UpstreamAccount',1;
END;
GO
CREATE PROCEDURE app.AuthLookup @kind VARCHAR(12),@account NVARCHAR(50)
WITH EXECUTE AS OWNER AS
BEGIN
 SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
 IF @kind='customer'
  SELECT user_id identity_id,password_hash,CAST('customer' AS VARCHAR(50)) role
  FROM dbo.Users WHERE username=@account AND status='active';
 ELSE IF @kind='employee'
  SELECT e.employee_id identity_id,e.password_hash,r.role_name role
  FROM dbo.Employees e JOIN dbo.Roles r ON r.role_id=e.role_id
  WHERE e.account=@account AND e.status='active' AND r.role_name IN('staff','admin');
 ELSE THROW 55000,'Invalid identity kind',1;
END;
GO
CREATE PROCEDURE app.StartSession @kind VARCHAR(12),@identity_id INT,@token_hash VARBINARY(32)
WITH EXECUTE AS OWNER AS
BEGIN
 SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
 IF @token_hash IS NULL OR DATALENGTH(@token_hash)<>32 THROW 55000,'Invalid session token',1;
 DECLARE @role VARCHAR(50),@user INT,@employee INT;
 IF @kind='customer'
  SELECT @role='customer',@user=user_id FROM dbo.Users WHERE user_id=@identity_id AND status='active';
 ELSE IF @kind='employee'
  SELECT @role=r.role_name,@employee=e.employee_id FROM dbo.Employees e JOIN dbo.Roles r ON r.role_id=e.role_id
  WHERE e.employee_id=@identity_id AND e.status='active' AND r.role_name IN('staff','admin');
 ELSE THROW 55000,'Invalid identity kind',1;
 IF @role IS NULL THROW 55001,'Inactive or missing identity',1;
 INSERT app.Sessions(token_hash,user_id,employee_id,expires_at)
 VALUES(@token_hash,@user,@employee,DATEADD(HOUR,8,SYSDATETIME()));
 SELECT @role role,@user user_id,@employee employee_id;
END;
GO
CREATE PROCEDURE app.ResolveSession @token_hash VARBINARY(32)
WITH EXECUTE AS OWNER AS
BEGIN
 SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
 SELECT CASE WHEN u.user_id IS NOT NULL THEN 'customer' ELSE r.role_name END role,s.user_id,s.employee_id
 FROM app.Sessions s
 LEFT JOIN dbo.Users u ON u.user_id=s.user_id AND u.status='active'
 LEFT JOIN dbo.Employees e ON e.employee_id=s.employee_id AND e.status='active'
 LEFT JOIN dbo.Roles r ON r.role_id=e.role_id AND r.role_name IN('staff','admin')
 WHERE DATALENGTH(@token_hash)=32 AND s.token_hash=@token_hash
 AND s.revoked_at IS NULL AND s.expires_at>SYSDATETIME()
 AND (u.user_id IS NOT NULL OR r.role_id IS NOT NULL);
END;
GO
CREATE PROCEDURE app.EndSession @token_hash VARBINARY(32)
WITH EXECUTE AS OWNER AS
BEGIN
 SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
 UPDATE app.Sessions SET revoked_at=SYSDATETIME()
 WHERE DATALENGTH(@token_hash)=32 AND token_hash=@token_hash AND revoked_at IS NULL;
END;
GO
:r sql/app/legacy_adapters.sql
CREATE PROCEDURE app.[Execute]
 @token_hash VARBINARY(32)=NULL,@operation VARCHAR(50),@payload NVARCHAR(MAX)=N'{}'
WITH EXECUTE AS OWNER AS
BEGIN
 SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF @payload IS NULL OR ISJSON(@payload)<>1 OR LEFT(LTRIM(@payload),1)<>'{' THROW 55000,'JSON object required',1;
 DECLARE @role VARCHAR(50),@user INT,@employee INT;
 -- Resolve internally; never trust actor identifiers or roles in the JSON payload.
 SELECT @role=CASE WHEN u.user_id IS NOT NULL THEN 'customer' ELSE r.role_name END,
        @user=s.user_id,@employee=s.employee_id
 FROM app.Sessions s WITH(HOLDLOCK)
 LEFT JOIN dbo.Users u ON u.user_id=s.user_id AND u.status='active'
 LEFT JOIN dbo.Employees e ON e.employee_id=s.employee_id AND e.status='active'
 LEFT JOIN dbo.Roles r ON r.role_id=e.role_id AND r.role_name IN('staff','admin')
 WHERE DATALENGTH(@token_hash)=32 AND s.token_hash=@token_hash
 AND s.revoked_at IS NULL AND s.expires_at>SYSDATETIME()
 AND (u.user_id IS NOT NULL OR r.role_id IS NOT NULL);
 IF @role IS NULL AND (@operation<>'products.list' OR @token_hash IS NOT NULL)
  THROW 55001,'Authentication required',1;
 DECLARE @page INT=COALESCE(TRY_CONVERT(INT,JSON_VALUE(@payload,'$.page')),1),
 @q NVARCHAR(100)=JSON_VALUE(@payload,'$.q'),@status VARCHAR(24)=JSON_VALUE(@payload,'$.status'),
 @id INT=TRY_CONVERT(INT,JSON_VALUE(@payload,'$.order_id')),
 @pid INT=TRY_CONVERT(INT,JSON_VALUE(@payload,'$.product_id')),
 @did INT=TRY_CONVERT(INT,JSON_VALUE(@payload,'$.detail_id')),
 @aid INT=TRY_CONVERT(INT,JSON_VALUE(@payload,'$.account_id')),
 @tid INT=TRY_CONVERT(INT,JSON_VALUE(@payload,'$.task_id')),
 @qty INT=TRY_CONVERT(INT,JSON_VALUE(@payload,'$.quantity')),
 @data NVARCHAR(MAX),@items NVARCHAR(MAX),@total INT,@owner INT,@ostatus VARCHAR(24);
 IF @page<1 OR @page>1000000 OR (JSON_VALUE(@payload,'$.page') IS NOT NULL AND TRY_CONVERT(INT,JSON_VALUE(@payload,'$.page')) IS NULL)
  THROW 55000,'Invalid page',1;
 IF LEN(JSON_VALUE(@payload,'$.q'))>100 THROW 55000,'Search too long',1;
 BEGIN TRY
 BEGIN TRANSACTION;
 IF @operation='products.list'
 BEGIN
  SET @items=(SELECT product_id,name,description,price,model_provider,token_amount,required_upstream_tokens,status
   FROM dbo.Products WHERE (@role IN('admin','staff') OR status='active')
   AND (@q IS NULL OR name LIKE N'%'+@q+N'%' OR description LIKE N'%'+@q+N'%')
   ORDER BY product_id OFFSET (@page-1)*20 ROWS FETCH NEXT 20 ROWS ONLY FOR JSON PATH);
  SELECT @total=COUNT(*) FROM dbo.Products WHERE (@role IN('admin','staff') OR status='active')
   AND (@q IS NULL OR name LIKE N'%'+@q+N'%' OR description LIKE N'%'+@q+N'%');
 END
 ELSE IF @operation IN('products.save','products.delete')
 BEGIN
  IF @role<>'admin' THROW 55003,'Administrator required',1;
  IF @operation='products.delete'
  BEGIN
   IF @pid IS NULL THROW 55000,'Product required',1;
   IF NOT EXISTS(SELECT 1 FROM dbo.Products WITH(UPDLOCK,HOLDLOCK) WHERE product_id=@pid) THROW 55004,'Product missing',1;
   IF EXISTS(SELECT 1 FROM dbo.OrderDetails WHERE product_id=@pid)
    OR EXISTS(SELECT 1 FROM dbo.TokenUsageLogs WHERE product_id=@pid)
    OR EXISTS(SELECT 1 FROM dbo.UsageSummaryCore WHERE product_id=@pid) THROW 55009,'Referenced product cannot be deleted',1;
   DELETE dbo.Products WHERE product_id=@pid;
  END
  ELSE
  BEGIN
   DECLARE @name NVARCHAR(100)=JSON_VALUE(@payload,'$.name'),@description NVARCHAR(MAX)=JSON_VALUE(@payload,'$.description'),
   @price DECIMAL(10,2)=TRY_CONVERT(DECIMAL(10,2),JSON_VALUE(@payload,'$.price')),
   @provider VARCHAR(50)=JSON_VALUE(@payload,'$.model_provider'),
   @tokens INT=TRY_CONVERT(INT,JSON_VALUE(@payload,'$.token_amount')),
   @required INT=TRY_CONVERT(INT,JSON_VALUE(@payload,'$.required_upstream_tokens'));
   IF NULLIF(TRIM(@name),N'') IS NULL OR LEN(JSON_VALUE(@payload,'$.name'))>100 OR @price IS NULL OR @price<=0
    OR @provider IS NULL OR @provider NOT IN('OpenAI','Claude','Gemini','Other') OR @tokens IS NULL OR @tokens<=0
    OR @required IS NULL OR @required<=0 OR @status IS NULL OR @status NOT IN('active','inactive','discontinued')
    THROW 55000,'Invalid product fields',1;
   IF JSON_VALUE(@payload,'$.product_id') IS NOT NULL AND @pid IS NULL THROW 55000,'Invalid product id',1;
   IF @pid IS NULL
   BEGIN
    INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status)
    VALUES(@name,@description,@price,@provider,@tokens,@required,@status);
    SET @pid=CONVERT(INT,SCOPE_IDENTITY());
   END
   ELSE
   BEGIN
    UPDATE dbo.Products SET name=@name,description=@description,price=@price,model_provider=@provider,
     token_amount=@tokens,required_upstream_tokens=@required,status=@status WHERE product_id=@pid;
    IF @@ROWCOUNT=0 THROW 55004,'Product missing',1;
   END;
  END;
  SET @data=(SELECT @pid product_id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 END
 ELSE IF @operation='orders.list'
 BEGIN
  SET @items=(SELECT order_id,user_id,total_amount,total_tokens,status,created_at,paid_at FROM dbo.Orders
   WHERE (@role IN('staff','admin') OR user_id=@user) AND (@status IS NULL OR status=@status)
    AND (@q IS NULL OR CONVERT(NVARCHAR(20),order_id) LIKE N'%'+@q+N'%')
   ORDER BY order_id DESC OFFSET (@page-1)*20 ROWS FETCH NEXT 20 ROWS ONLY FOR JSON PATH);
  SELECT @total=COUNT(*) FROM dbo.Orders WHERE (@role IN('staff','admin') OR user_id=@user) AND (@status IS NULL OR status=@status)
   AND (@q IS NULL OR CONVERT(NVARCHAR(20),order_id) LIKE N'%'+@q+N'%');
 END
 ELSE IF @operation='orders.create'
 BEGIN
  IF @role<>'customer' THROW 55003,'Customer required',1;
  DECLARE @newitems TABLE(seq INT PRIMARY KEY,product_id INT,quantity INT);
  IF LEFT(LTRIM(JSON_QUERY(@payload,'$.items')),1)<>'[' OR JSON_QUERY(@payload,'$.items') IS NULL THROW 55000,'Items array required',1;
  INSERT @newitems SELECT TRY_CONVERT(INT,[key]),TRY_CONVERT(INT,JSON_VALUE(value,'$.product_id')),TRY_CONVERT(INT,JSON_VALUE(value,'$.quantity')) FROM OPENJSON(@payload,'$.items');
  IF NOT EXISTS(SELECT 1 FROM @newitems) OR EXISTS(SELECT 1 FROM @newitems WHERE product_id IS NULL OR product_id<=0 OR quantity IS NULL OR quantity<=0)
   OR (SELECT COUNT(*) FROM @newitems)>100 THROW 55000,'One to 100 valid items required',1;
  EXEC dbo.usp_W5_CreateRegisteredOrder @user_id=@user,@emit_result=0,@app_result_id=@id OUTPUT;
  DECLARE @seq INT=-1;
  WHILE EXISTS(SELECT 1 FROM @newitems WHERE seq>@seq)
  BEGIN
   SELECT TOP(1) @seq=seq,@pid=product_id,@qty=quantity FROM @newitems WHERE seq>@seq ORDER BY seq;
   EXEC dbo.usp_W5_AddMergedOrderItem @order_id=@id,@product_id=@pid,@quantity=@qty,@emit_result=0;
  END;
  SET @data=(SELECT @id order_id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 END
 ELSE IF @operation IN('orders.get','orders.item_add','orders.item_set','orders.item_delete','orders.cancel','orders.delete','orders.pay','refunds.request','refunds.settle')
 BEGIN
  IF @id IS NULL OR @id<=0 THROW 55000,'Order required',1;
  SELECT @owner=user_id,@ostatus=status FROM dbo.Orders WITH(UPDLOCK,HOLDLOCK) WHERE order_id=@id;
  IF @owner IS NULL THROW 55004,'Order missing',1;
  IF @role='customer' AND @owner<>@user THROW 55003,'Order belongs to another customer',1;
  IF @operation='orders.get'
   SET @data=(SELECT JSON_QUERY((SELECT order_id,user_id,total_amount,total_tokens,status,created_at,paid_at FROM dbo.Orders WHERE order_id=@id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER)) [order],
    JSON_QUERY((SELECT d.*,p.name,p.model_provider FROM dbo.OrderDetails d JOIN dbo.Products p ON p.product_id=d.product_id WHERE d.order_id=@id ORDER BY d.detail_id FOR JSON PATH)) items FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  ELSE
  BEGIN
   IF @operation IN('orders.item_add','orders.item_set','orders.item_delete','orders.pay','refunds.request') AND @role<>'customer' THROW 55003,'Customer required',1;
   IF @operation IN('orders.item_add','orders.item_set','orders.item_delete','orders.cancel','orders.pay') AND @ostatus<>'pending' THROW 55009,'Pending order required',1;
   IF @operation='orders.item_add'
   BEGIN
    IF @pid IS NULL OR @pid<=0 OR @qty IS NULL OR @qty<=0 THROW 55000,'Product and positive quantity required',1;
    EXEC dbo.usp_W5_AddMergedOrderItem @id,@pid,@qty,@emit_result=0;
   END
   ELSE IF @operation IN('orders.item_set','orders.item_delete')
   BEGIN
    IF @did IS NULL OR @did<=0 THROW 55000,'Detail required',1;
    IF NOT EXISTS(SELECT 1 FROM dbo.OrderDetails WITH(UPDLOCK,HOLDLOCK) WHERE detail_id=@did AND order_id=@id) THROW 55004,'Order item missing',1;
    IF @operation='orders.item_set'
    BEGIN
     IF @qty IS NULL OR @qty<=0 THROW 55000,'Positive quantity required',1;
     UPDATE dbo.OrderDetails SET quantity=@qty,subtotal=CONVERT(DECIMAL(10,2),CONVERT(DECIMAL(18,2),@qty)*unit_price),total_tokens=CONVERT(BIGINT,@qty)*tokens_per_unit WHERE detail_id=@did AND order_id=@id;
    END
    ELSE DELETE dbo.OrderDetails WHERE detail_id=@did AND order_id=@id;
    UPDATE dbo.Orders SET total_amount=(SELECT COALESCE(SUM(subtotal),0) FROM dbo.OrderDetails WHERE order_id=@id),total_tokens=(SELECT COALESCE(SUM(total_tokens),0) FROM dbo.OrderDetails WHERE order_id=@id) WHERE order_id=@id;
   END
   ELSE IF @operation='orders.cancel' UPDATE dbo.Orders SET status='cancelled' WHERE order_id=@id;
   ELSE IF @operation='orders.delete'
   BEGIN
    IF @role<>'admin' THROW 55003,'Administrator required',1;
    IF @ostatus NOT IN('pending','cancelled') OR EXISTS(SELECT 1 FROM dbo.OrderDetails WHERE order_id=@id)
     OR EXISTS(SELECT 1 FROM dbo.RefundLedger WHERE order_id=@id) OR EXISTS(SELECT 1 FROM dbo.OrderTokenLots l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id WHERE d.order_id=@id) OR EXISTS(SELECT 1 FROM dbo.InventoryLog WHERE reference_type='order' AND reference_id=@id) OR EXISTS(SELECT 1 FROM dbo.ExceptionLog WHERE related_table='Orders' AND related_id=@id)
     THROW 55009,'Only empty unfinalized orders can be deleted',1;
    DELETE dbo.Orders WHERE order_id=@id;
   END
   ELSE IF @operation='orders.pay'
   BEGIN
    EXEC dbo.usp_W6_PayPendingOrder @id,@emit_result=0;
   END
   ELSE IF @operation='refunds.request'
   BEGIN
    EXEC dbo.usp_W6_RequestRefund @id,@emit_result=0;
   END
   ELSE IF @operation='refunds.settle'
   BEGIN
    IF @role<>'admin' THROW 55003,'Administrator required',1;
    DECLARE @ref VARCHAR(120)=CONCAT('SIM-',@id);
    EXEC dbo.usp_W6_AttestRefundPayout @id,@ref,@employee,@emit_result=0;
   END;
   SET @data=(SELECT @id order_id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
  END;
 END
 ELSE IF @operation='usage.list'
 BEGIN
  SET @items=(SELECT l.log_id,l.user_id,l.product_id,p.name,p.model_provider,l.account_id,l.tokens_used,l.upstream_tokens_consumed,l.api_endpoint,l.used_at
   FROM dbo.TokenUsageLogs l JOIN dbo.Products p ON p.product_id=l.product_id
   WHERE @role IN('staff','admin') OR l.user_id=@user ORDER BY l.log_id DESC OFFSET (@page-1)*20 ROWS FETCH NEXT 20 ROWS ONLY FOR JSON PATH);
  SELECT @total=COUNT(*) FROM dbo.TokenUsageLogs WHERE @role IN('staff','admin') OR user_id=@user;
 END
 ELSE IF @operation='usage.create'
 BEGIN
  IF @role<>'customer' THROW 55003,'Customer required',1;
  DECLARE @used INT=TRY_CONVERT(INT,JSON_VALUE(@payload,'$.tokens_used')),@upstream INT;
  IF @pid IS NULL OR @pid<=0 OR @used IS NULL OR @used<=0 THROW 55000,'Product and positive usage required',1;
  SELECT @provider=model_provider,@upstream=TRY_CONVERT(INT,(CONVERT(BIGINT,@used)*required_upstream_tokens+token_amount-1)/token_amount)
  FROM dbo.Products WITH(UPDLOCK,HOLDLOCK) WHERE product_id=@pid AND status='active';
  IF @provider IS NULL THROW 55004,'Active product missing',1;
  IF @upstream IS NULL OR @upstream<=0 THROW 55000,'Usage exceeds supported range',1;
  SET @aid=NULL;
  SELECT TOP(1) @aid=a.account_id FROM dbo.UpstreamAccount a WITH(UPDLOCK,HOLDLOCK)
   JOIN dbo.Inventory i WITH(UPDLOCK,HOLDLOCK) ON i.account_id=a.account_id
   WHERE a.provider=@provider AND a.status='active' AND a.created_at<=SYSDATETIME()
   AND (a.expires_at IS NULL OR a.expires_at>SYSDATETIME()) AND i.current_quota>=@upstream
   AND a.total_quota-a.used_quota=i.current_quota ORDER BY a.account_id;
  IF @aid IS NULL THROW 55009,'No eligible upstream account with sufficient inventory',1;
  DECLARE @usage_id INT;
  EXEC dbo.usp_W5_RecordUsage @user,@pid,@aid,@used,@upstream,'/simulation',@emit_result=0,@app_result_id=@usage_id OUTPUT;
  SET @data=(SELECT @usage_id log_id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 END
 ELSE IF @operation='balances.list'
 BEGIN
  SET @items=(SELECT balance_id,user_id,model_provider,remaining_tokens,updated_at FROM dbo.TokenBalances WHERE @role IN('staff','admin') OR user_id=@user ORDER BY balance_id OFFSET (@page-1)*20 ROWS FETCH NEXT 20 ROWS ONLY FOR JSON PATH);
  SELECT @total=COUNT(*) FROM dbo.TokenBalances WHERE @role IN('staff','admin') OR user_id=@user;
 END
 ELSE IF @operation='inventory.list'
 BEGIN
  IF @role NOT IN('staff','admin') THROW 55003,'Employee required',1;
  SET @items=(SELECT a.account_id,a.provider,a.account_name,a.total_quota,a.used_quota,a.safety_threshold,a.status,a.expires_at,a.created_at,a.updated_at,i.current_quota,
   CASE WHEN a.status='active' AND a.created_at<=SYSDATETIME() AND (a.expires_at IS NULL OR a.expires_at>SYSDATETIME()) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END available,
   CASE WHEN i.current_quota<a.safety_threshold THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END low_quota
   FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id ORDER BY a.account_id OFFSET (@page-1)*20 ROWS FETCH NEXT 20 ROWS ONLY FOR JSON PATH);
  SELECT @total=COUNT(*) FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id;
 END
 ELSE IF @operation IN('accounts.save','accounts.delete')
 BEGIN
  IF @role<>'admin' THROW 55003,'Administrator required',1;
  IF @operation='accounts.delete'
  BEGIN
   IF @aid IS NULL OR @aid<=0 THROW 55000,'Account required',1;
   IF NOT EXISTS(SELECT 1 FROM dbo.UpstreamAccount WITH(UPDLOCK,HOLDLOCK) WHERE account_id=@aid) THROW 55004,'Account missing',1;
   IF EXISTS(SELECT 1 FROM dbo.TokenUsageLogs WHERE account_id=@aid) OR EXISTS(SELECT 1 FROM dbo.InventoryLog WHERE account_id=@aid
    AND (reason IS NULL OR reason<>N'APP_INITIAL_QUOTA_V1' OR change_type<>'purchase' OR reference_type IS NULL OR reference_type<>'manual' OR reference_id IS NOT NULL))
    OR EXISTS(SELECT 1 FROM dbo.RestockTask WHERE account_id=@aid) THROW 55009,'Referenced account cannot be deleted',1;
   EXEC sys.sp_set_session_context @key=N'app_account_delete',@value=1;
   DELETE dbo.InventoryLog WHERE account_id=@aid AND reason=N'APP_INITIAL_QUOTA_V1';
   DELETE dbo.Inventory WHERE account_id=@aid;
   DELETE dbo.UpstreamAccount WHERE account_id=@aid;
   EXEC sys.sp_set_session_context @key=N'app_account_delete',@value=NULL;
  END
  ELSE
  BEGIN
   DECLARE @aname NVARCHAR(100)=JSON_VALUE(@payload,'$.account_name'),@quota BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@payload,'$.total_quota')),
    @threshold BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@payload,'$.safety_threshold')),
    @expiry DATETIME2(0)=TRY_CONVERT(DATETIME2(0),JSON_VALUE(@payload,'$.expires_at'),126);
   SET @provider=JSON_VALUE(@payload,'$.provider');
   IF @provider IS NULL OR @provider NOT IN('OpenAI','Claude','Gemini','Other') OR NULLIF(TRIM(@aname),N'') IS NULL OR LEN(JSON_VALUE(@payload,'$.account_name'))>100
    OR @threshold IS NULL OR @threshold<0 OR @status IS NULL OR @status NOT IN('active','suspended','depleted','expired')
    OR (JSON_VALUE(@payload,'$.expires_at') IS NOT NULL AND @expiry IS NULL)
    OR EXISTS(SELECT 1 FROM OPENJSON(@payload) WHERE [key]='used_quota') THROW 55000,'Invalid account fields',1;
   IF JSON_VALUE(@payload,'$.account_id') IS NOT NULL AND @aid IS NULL THROW 55000,'Invalid account id',1;
   IF @aid IS NULL
   BEGIN
    IF @quota IS NULL OR @quota<=0 THROW 55000,'Positive initial quota required',1;
    INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,safety_threshold,status,expires_at)
     VALUES(@provider,@aname,N'SIMULATION-NO-EXTERNAL-KEY',@quota,@threshold,@status,@expiry);
    SET @aid=CONVERT(INT,SCOPE_IDENTITY());
    IF NOT EXISTS(SELECT 1 FROM dbo.Inventory WHERE account_id=@aid AND current_quota=@quota) THROW 55009,'Inventory pair missing',1;
   END
   ELSE
   BEGIN
    IF EXISTS(SELECT 1 FROM OPENJSON(@payload) WHERE [key]='total_quota') THROW 55000,'Use restock workflow to change quota',1;
    UPDATE dbo.UpstreamAccount SET provider=@provider,account_name=@aname,safety_threshold=@threshold,status=@status,expires_at=@expiry,updated_at=SYSDATETIME() WHERE account_id=@aid;
    IF @@ROWCOUNT=0 THROW 55004,'Account missing',1;
   END;
  END;
  SET @data=(SELECT @aid account_id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 END
 ELSE IF @operation='restocks.list'
 BEGIN
  IF @role NOT IN('staff','admin') THROW 55003,'Employee required',1;
  SET @items=(SELECT t.*,a.account_name,a.provider FROM dbo.RestockTask t JOIN dbo.UpstreamAccount a ON a.account_id=t.account_id ORDER BY t.task_id DESC OFFSET (@page-1)*20 ROWS FETCH NEXT 20 ROWS ONLY FOR JSON PATH);
  SELECT @total=COUNT(*) FROM dbo.RestockTask;
 END
 ELSE IF @operation IN('restocks.create','restocks.complete')
 BEGIN
  IF @role NOT IN('staff','admin') THROW 55003,'Employee required',1;
  IF @operation='restocks.create'
  BEGIN
   DECLARE @planned BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@payload,'$.planned_amount'));
   IF @aid IS NULL OR @aid<=0 OR @planned IS NULL OR @planned<=0 THROW 55000,'Account and positive planned amount required',1;
   IF NOT EXISTS(SELECT 1 FROM dbo.UpstreamAccount WITH(UPDLOCK,HOLDLOCK) WHERE account_id=@aid) THROW 55004,'Account missing',1;
   INSERT dbo.RestockTask(account_id,trigger_reason,restock_method,target_amount,created_by,assigned_to,status)
    VALUES(@aid,'manual','manual_purchase',@planned,@employee,@employee,'pending');
   SET @tid=CONVERT(INT,SCOPE_IDENTITY());
  END
  ELSE
  BEGIN
   DECLARE @actual BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@payload,'$.actual_amount'));
   IF @tid IS NULL OR @tid<=0 OR @actual IS NULL OR @actual<=0 THROW 55000,'Task and positive actual amount required',1;
   IF NOT EXISTS(SELECT 1 FROM dbo.RestockTask WITH(UPDLOCK,HOLDLOCK) WHERE task_id=@tid) THROW 55004,'Task missing',1;
   IF NOT EXISTS(SELECT 1 FROM dbo.RestockTask WHERE task_id=@tid AND status IN('pending','in_progress')) THROW 55009,'Task finalized',1;
   UPDATE dbo.RestockTask SET assigned_to=@employee WHERE task_id=@tid;
   EXEC dbo.usp_W6_RestockAccount @tid,@actual,@emit_result=0;
  END;
  SET @data=(SELECT @tid task_id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 END
 ELSE IF @operation='refunds.list'
 BEGIN
  SET @items=(SELECT r.* FROM dbo.RefundLedger r JOIN dbo.Orders o ON o.order_id=r.order_id WHERE @role IN('staff','admin') OR o.user_id=@user ORDER BY r.refund_id DESC OFFSET (@page-1)*20 ROWS FETCH NEXT 20 ROWS ONLY FOR JSON PATH);
  SELECT @total=COUNT(*) FROM dbo.RefundLedger r JOIN dbo.Orders o ON o.order_id=r.order_id WHERE @role IN('staff','admin') OR o.user_id=@user;
 END
 ELSE THROW 55000,'Unknown operation',1;
 IF @operation IN('products.list','orders.list','usage.list','balances.list','inventory.list','restocks.list','refunds.list') SET @data=(SELECT JSON_QUERY(COALESCE(@items,N'[]')) items,@total total,@page page,20 page_size FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 COMMIT TRANSACTION;
 SELECT @data data;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  EXEC sys.sp_set_session_context @key=N'app_account_delete',@value=NULL;
  THROW;
 END CATCH;
END;
GO
GRANT EXECUTE ON app.AuthLookup TO app_runtime;
GRANT EXECUTE ON app.StartSession TO app_runtime;
GRANT EXECUTE ON app.ResolveSession TO app_runtime;
GRANT EXECUTE ON app.EndSession TO app_runtime;
GRANT EXECUTE ON app.[Execute] TO app_runtime;
GO



COMMIT TRANSACTION;
GO
