USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
CREATE TABLE #RoleCases(
  case_id VARCHAR(4) PRIMARY KEY,actor SYSNAME,
  statement_sql NVARCHAR(MAX),expected_error INT
);
INSERT #RoleCases VALUES
('R01','hub_guest_demo',N'IF (SELECT COUNT(*) FROM dbo.v_ProductCatalog)<>10 THROW 51201,N''Catalog count mismatch'',1;',0),
('R02','hub_guest_demo',N'SELECT TOP(1) order_id FROM dbo.Orders;',229),
('R03','hub_staff_demo',N'IF (SELECT COUNT(*) FROM dbo.v_OrderDetail)<>184 THROW 51203,N''Detail count mismatch'',1;',0),
('R04','hub_staff_demo',N'UPDATE dbo.Products SET price=price+1 WHERE product_id=1;',229),
('R05','hub_staff_demo',N'DECLARE @id INT=(SELECT MIN(order_id) FROM dbo.v_StaffOrderQueue WHERE status=''pending''); IF @id IS NULL THROW 51205,N''Missing pending order'',1; UPDATE dbo.v_StaffOrderQueue SET status=''cancelled'' WHERE order_id=@id; IF @@ROWCOUNT<>1 THROW 51206,N''Update count mismatch'',1;',0),
('R06','hub_user_1',N'IF (SELECT COUNT(*) FROM dbo.v_MyOrders)<>13 OR EXISTS(SELECT 1 FROM dbo.v_MyOrders WHERE user_id<>1) THROW 51207,N''User 1 isolation failed'',1; SELECT * FROM dbo.v_MyOrders ORDER BY order_id;',0),
('R07','hub_user_2',N'IF (SELECT COUNT(*) FROM dbo.v_MyOrders)<>15 OR EXISTS(SELECT 1 FROM dbo.v_MyOrders WHERE user_id<>2) THROW 51208,N''User 2 isolation failed'',1; SELECT * FROM dbo.v_MyOrders ORDER BY order_id;',0),
('R08','hub_user_1',N'SELECT TOP(1) order_id FROM dbo.Orders;',229),
('R09','hub_user_1',N'SELECT api_key FROM dbo.UpstreamAccount;',229),
('R10','hub_user_1',N'IF EXISTS(SELECT 1 FROM dbo.v_MyOrders WHERE user_id=2) THROW 51210,N''Other user visible'',1; IF NOT EXISTS(SELECT 1 FROM dbo.v_MyBalances) OR EXISTS(SELECT 1 FROM dbo.v_MyBalances WHERE user_id<>1) THROW 51211,N''Balance isolation failed'',1; IF NOT EXISTS(SELECT 1 FROM dbo.v_MyUsage) OR EXISTS(SELECT 1 FROM dbo.v_MyUsage WHERE user_id<>1) THROW 51212,N''Usage isolation failed'',1;',0),
('R11','hub_manager_demo',N'UPDATE dbo.Products SET price=price+1 WHERE product_id=1; IF @@ROWCOUNT<>1 THROW 51213,N''Manager update failed'',1;',0),
('R12','hub_manager_demo',N'IF COALESCE(HAS_PERMS_BY_NAME(DB_NAME(),''DATABASE'',''CREATE TABLE''),0)<>0 OR COALESCE(HAS_PERMS_BY_NAME(DB_NAME(),''DATABASE'',''CONTROL''),0)<>0 THROW 51214,N''Manager overprivileged'',1;',0),
('R13','hub_staff_demo',N'UPDATE dbo.v_StaffOrderQueue SET user_id=user_id WHERE order_id=(SELECT MIN(order_id) FROM dbo.v_StaffOrderQueue);',230),
('R14','hub_staff_demo',N'IF EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N''dbo.v_CustomerService'',N''V'') AND name IN(N''password_hash'',N''api_key'')) THROW 51214,N''Sensitive column exposed in service view'',1; IF (SELECT COUNT(*) FROM dbo.v_CustomerService)<>40 THROW 51215,N''Customer service row count mismatch'',1; SELECT TOP(5) user_id,username,email,phone,status,order_count,paid_amount,remaining_tokens FROM dbo.v_CustomerService ORDER BY paid_amount DESC,user_id;',0),
('R15','hub_staff_demo',N'SELECT TOP(1) password_hash FROM dbo.Users;',229),
('R16','hub_user_1',N'SELECT TOP(1) email FROM dbo.v_CustomerService;',229),
('R17','hub_manager_demo',N'IF (SELECT COUNT(*) FROM dbo.v_CustomerService)<>40 THROW 51217,N''Manager service view mismatch'',1;',0);
DELETE FROM #RoleCases WHERE case_id NOT IN ('R06','R07','R10');
GO
DECLARE @case VARCHAR(4),@actor SYSNAME,@stmt NVARCHAR(MAX),@want INT,
        @got INT,@msg NVARCHAR(4000),@switched BIT,@pass_count INT=0,
        @original SYSNAME=USER_NAME();
DECLARE role_cases CURSOR LOCAL FAST_FORWARD FOR
SELECT case_id,actor,statement_sql,expected_error FROM #RoleCases ORDER BY case_id;
OPEN role_cases;
FETCH NEXT FROM role_cases INTO @case,@actor,@stmt,@want;
WHILE @@FETCH_STATUS=0
BEGIN
    SELECT @got=0,@msg=N'',@switched=0;
    BEGIN TRY
        BEGIN TRANSACTION;
        EXECUTE AS USER=@actor;
        SET @switched=1;
        EXEC sys.sp_executesql @stmt;
        REVERT;
        SET @switched=0;
        ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH
        SELECT @got=ERROR_NUMBER(),@msg=ERROR_MESSAGE();
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        IF @switched=1 REVERT;
        SET @switched=0;
    END CATCH;
    IF USER_NAME()<>@original THROW 51298,N'Execution context not restored',1;
    IF @got<>@want
    BEGIN
        SET @msg=CONCAT(@case,N' failed; expected=',@want,N'; actual=',@got,N'; ',@msg);
        THROW 51299,@msg,1;
    END;
    SET @pass_count+=1;
    SELECT @case AS case_id,@actor AS actor,N'PASS' AS result,
           @got AS actual_error,@msg AS actual_message;
    FETCH NEXT FROM role_cases INTO @case,@actor,@stmt,@want;
END;
CLOSE role_cases;
DEALLOCATE role_cases;
DROP TABLE #RoleCases;
IF @pass_count<>3 THROW 51297,N'Expected 3 selected PASS cases',1;
IF @@TRANCOUNT<>0 THROW 51296,N'Open transaction after role tests',1;
GO
EXECUTE AS USER='hub_staff_demo';
PRINT N'R14 Staff permissions on queue view and customer service view';
SELECT * FROM sys.fn_my_permissions('dbo.v_StaffOrderQueue','OBJECT');
SELECT * FROM sys.fn_my_permissions('dbo.v_CustomerService','OBJECT');
REVERT;
PRINT N'R15 Staff permissions on dbo.Users base table (expect no SELECT)';
EXECUTE AS USER='hub_staff_demo';
SELECT * FROM sys.fn_my_permissions('dbo.Users','OBJECT');
REVERT;

IF EXISTS(
    SELECT 1 FROM sys.database_role_members m
    JOIN sys.database_principals r ON r.principal_id=m.role_principal_id
    JOIN sys.database_principals u ON u.principal_id=m.member_principal_id
    WHERE r.is_fixed_role=1 AND u.name IN
      ('hub_manager','hub_staff','hub_customer','hub_guest','hub_manager_demo',
       'hub_staff_demo','hub_user_1','hub_user_2','hub_guest_demo')
) THROW 51290,N'Unexpected fixed-role membership',1;

IF EXISTS(
    SELECT 1 FROM sys.database_permissions p
    JOIN sys.objects o ON o.object_id=p.major_id
    WHERE p.class=1 AND p.grantee_principal_id=DATABASE_PRINCIPAL_ID('public')
      AND o.schema_id=SCHEMA_ID('dbo') AND o.type IN ('U','V')
      AND p.state IN ('G','W')
) THROW 51291,N'Public has business-object access',1;

EXECUTE AS USER='hub_user_1';
DECLARE @can_impersonate INT=HAS_PERMS_BY_NAME('hub_user_2','USER','IMPERSONATE');
REVERT;
IF COALESCE(@can_impersonate,0)<>0 THROW 51292,N'Customer can impersonate another user',1;
IF USER_NAME()<>N'dbo' THROW 51293,N'Execution context not dbo at script end',1;
IF @@TRANCOUNT<>0 THROW 51294,N'Open transaction at role script end',1;
PRINT N'PASS selected role cases and permission audit';
GO
