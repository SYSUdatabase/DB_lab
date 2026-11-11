-- VFY14 isolated from sql/verify.sql after inherited VFY12/13 failures.
SET NOCOUNT ON;
PRINT N'VFY14 Effective permissions for demonstration users';
-- 先在 dbo 下取对象清单，防止低权限用户看不见元数据而漏检。
DECLARE @objects TABLE(object_name NVARCHAR(260));
INSERT @objects SELECT N'dbo.'+name FROM sys.tables WHERE is_ms_shipped=0;
DECLARE @actors TABLE(actor SYSNAME,kind VARCHAR(20));
INSERT @actors VALUES('hub_manager_demo','manager'),('hub_staff_demo','staff'),
                     ('hub_user_1','customer'),('hub_user_2','customer'),('hub_guest_demo','guest');
DECLARE @actor SYSNAME,@kind VARCHAR(20),@object NVARCHAR(260),@stmt NVARCHAR(MAX);
DECLARE effective_permissions CURSOR LOCAL FAST_FORWARD FOR
SELECT a.actor,a.kind,o.object_name FROM @actors a CROSS JOIN @objects o;
OPEN effective_permissions;
FETCH NEXT FROM effective_permissions INTO @actor,@kind,@object;
WHILE @@FETCH_STATUS=0
BEGIN
    IF @kind='manager'
        SET @stmt=N'IF EXISTS(SELECT 1 FROM (VALUES(''SELECT''),(''INSERT''),(''UPDATE''),(''DELETE'')) p(name)
            WHERE COALESCE(HAS_PERMS_BY_NAME(@object,''OBJECT'',p.name),0)<>1)
            THROW 51364,N''Manager effective CRUD missing'',1;';
    ELSE
        SET @stmt=N'IF EXISTS(SELECT 1 FROM sys.fn_my_permissions(@object,''OBJECT''))
            THROW 51366,N''Non-manager has effective base-table access'',1;';
    EXECUTE AS USER=@actor;
    BEGIN TRY
        EXEC sys.sp_executesql @stmt,N'@object NVARCHAR(260)',@object=@object;
        REVERT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()=-1 ROLLBACK TRANSACTION;
        REVERT;
        THROW;
    END CATCH;
    FETCH NEXT FROM effective_permissions INTO @actor,@kind,@object;
END;
CLOSE effective_permissions;
DEALLOCATE effective_permissions;
-- 会员/游客即使被直接授予视图写权限，也必须被有效权限验收捕获。
DECLARE readonly_views CURSOR LOCAL FAST_FORWARD FOR
SELECT a.actor,N'dbo.'+v.name FROM @actors a CROSS JOIN sys.views v
WHERE a.kind IN ('customer','guest') AND v.is_ms_shipped=0;
OPEN readonly_views;
FETCH NEXT FROM readonly_views INTO @actor,@object;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @stmt=N'IF EXISTS(SELECT 1 FROM sys.fn_my_permissions(@object,''OBJECT'')
        WHERE permission_name IN(''INSERT'',''UPDATE'',''DELETE'',''CONTROL'',''ALTER''))
        THROW 51368,N''Read-only actor has effective view write permission'',1;';
    EXECUTE AS USER=@actor;
    BEGIN TRY
        EXEC sys.sp_executesql @stmt,N'@object NVARCHAR(260)',@object=@object;
        REVERT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()=-1 ROLLBACK TRANSACTION;
        REVERT;
        THROW;
    END CATCH;
    FETCH NEXT FROM readonly_views INTO @actor,@object;
END;
CLOSE readonly_views;
DEALLOCATE readonly_views;
IF USER_NAME()<>N'dbo' OR @@TRANCOUNT<>0 THROW 51367,N'Verification context not restored',1;
PRINT N'PASS VFY14 effective permission checks';
PRINT N'PASS v1.0 isolated VFY14 permissions';
GO
