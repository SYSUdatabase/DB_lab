-- Employee management extension. Only active administrators may call it.
-- Install after app/install.sql. Restricted to isolated Web v1.1 databases.
:on error exit
USE [$(DatabaseName)];
GO
IF DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]Web%'
    THROW 55000,'Employee management installation restricted to Web test databases',1;
IF OBJECT_ID(N'app.Sessions',N'U') IS NULL OR DATABASE_PRINCIPAL_ID(N'app_runtime') IS NULL
    THROW 55000,'Web application must be installed before employee management',1;
GO
CREATE OR ALTER PROCEDURE app.ManageEmployees
    @token_hash VARBINARY(32),
    @operation VARCHAR(40),
    @payload NVARCHAR(MAX)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @payload IS NULL OR ISJSON(@payload)<>1 OR LEFT(LTRIM(@payload),1)<>'{'
       THROW 55000,'Invalid employee payload',1;

    DECLARE @actor INT;
    SELECT @actor=e.employee_id
      FROM app.Sessions s
      JOIN dbo.Employees e ON e.employee_id=s.employee_id AND e.status='active'
      JOIN dbo.Roles r ON r.role_id=e.role_id AND r.role_name='admin'
     WHERE DATALENGTH(@token_hash)=32 AND s.token_hash=@token_hash
       AND s.revoked_at IS NULL AND s.expires_at>SYSDATETIME();
    IF @actor IS NULL THROW 55003,'Administrator required',1;

    IF @operation='employees.list'
    BEGIN
        DECLARE @page INT=TRY_CONVERT(INT,JSON_VALUE(@payload,'$.page'));
        IF @page IS NULL OR @page<1 OR @page>100000 THROW 55000,'Invalid page',1;
        DECLARE @list NVARCHAR(MAX)=(SELECT e.employee_id,e.name,e.account,e.status,e.hire_date,
                       r.role_name role
                  FROM dbo.Employees e JOIN dbo.Roles r ON r.role_id=e.role_id
                 WHERE r.role_name='staff'
                 ORDER BY e.employee_id DESC
                 OFFSET (@page-1)*20 ROWS FETCH NEXT 20 ROWS ONLY FOR JSON PATH);
        SELECT (SELECT JSON_QUERY(COALESCE(@list,N'[]')) AS items,
                  (SELECT COUNT(*) FROM dbo.Employees e JOIN dbo.Roles r ON r.role_id=e.role_id
                   WHERE r.role_name='staff') AS total, @page AS page, 20 AS page_size
                FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS data;
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;
        DECLARE @id INT=TRY_CONVERT(INT,JSON_VALUE(@payload,'$.employee_id')),
                @name NVARCHAR(50)=JSON_VALUE(@payload,'$.name'),
                @account VARCHAR(50)=JSON_VALUE(@payload,'$.account'),
                @hash VARCHAR(60)=JSON_VALUE(@payload,'$.password_hash'),
                @status VARCHAR(20)=JSON_VALUE(@payload,'$.status');
        DECLARE @out INT;
        IF @operation='employees.create'
        BEGIN
            IF @name IS NULL OR LEN(LTRIM(RTRIM(@name))) NOT BETWEEN 1 AND 50
                OR @account IS NULL OR LEN(@account) NOT BETWEEN 3 AND 50
                OR @account COLLATE Latin1_General_BIN2 LIKE '%[^A-Za-z0-9_]%'
                THROW 55000,'Invalid staff identity',1;
            IF @hash IS NULL OR DATALENGTH(@hash)<>60
                OR LEFT(@hash,4) NOT IN ('$2a$','$2b$','$2y$')
                THROW 55000,'Invalid password hash',1;
            DECLARE @created TABLE(employee_id INT);
            INSERT dbo.Employees(name,role_id,account,password_hash)
                OUTPUT inserted.employee_id INTO @created
            SELECT @name,r.role_id,@account,@hash
              FROM dbo.Roles r WHERE r.role_name='staff';
            SELECT @out=employee_id FROM @created;
            IF @out IS NULL THROW 55004,'Staff role missing',1;
        END
        ELSE IF @operation IN ('employees.update','employees.password','employees.status')
        BEGIN
            IF @id IS NULL OR @id<1 THROW 55000,'Invalid employee ID',1;
            IF NOT EXISTS(
                SELECT 1 FROM dbo.Employees e WITH(UPDLOCK,HOLDLOCK)
                JOIN dbo.Roles r ON r.role_id=e.role_id
                WHERE e.employee_id=@id AND r.role_name='staff'
            ) THROW 55004,'Staff member missing',1;
            IF @operation='employees.update'
            BEGIN
                IF @name IS NULL OR LEN(LTRIM(RTRIM(@name))) NOT BETWEEN 1 AND 50
                    THROW 55000,'Invalid employee name',1;
                UPDATE dbo.Employees SET name=@name WHERE employee_id=@id;
            END
            ELSE IF @operation='employees.password'
            BEGIN
                IF @hash IS NULL OR DATALENGTH(@hash)<>60
                    OR LEFT(@hash,4) NOT IN ('$2a$','$2b$','$2y$')
                    THROW 55000,'Invalid password hash',1;
                UPDATE dbo.Employees SET password_hash=@hash WHERE employee_id=@id;
                UPDATE app.Sessions SET revoked_at=SYSDATETIME()
                    WHERE employee_id=@id AND revoked_at IS NULL;
            END
            ELSE
            BEGIN
                IF @status NOT IN('active','inactive') OR @status IS NULL
                    THROW 55000,'Invalid status',1;
                UPDATE dbo.Employees SET status=@status WHERE employee_id=@id;
                IF @status='inactive'
                    UPDATE app.Sessions SET revoked_at=SYSDATETIME()
                    WHERE employee_id=@id AND revoked_at IS NULL;
            END
            SET @out=@id;
        END
        ELSE THROW 55000,'Unknown employee operation',1;
        COMMIT TRANSACTION;
        SELECT (SELECT @out AS employee_id FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) AS data;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
GRANT EXECUTE ON app.ManageEmployees TO app_runtime;
GO
