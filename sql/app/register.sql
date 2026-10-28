-- Register ordinary customers only; deploy after sql/app/install.sql.
-- Re-runnable in separately prepared Web v1.1 databases; never touches legacy DBs.
:on error exit
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
IF DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]Web%'
    THROW 55000, 'Registration extension is restricted to isolated Web databases', 1;
IF SCHEMA_ID(N'app') IS NULL OR DATABASE_PRINCIPAL_ID(N'app_runtime') IS NULL
    THROW 55000, 'Install the Web app extension before registration', 1;
GO
CREATE OR ALTER PROCEDURE app.RegisterCustomer
    @username VARCHAR(50),
    @email VARCHAR(100),
    @password_hash VARCHAR(60)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @username IS NULL OR LEN(@username) NOT BETWEEN 3 AND 50
       OR @username COLLATE Latin1_General_BIN2 LIKE '%[^A-Za-z0-9_]%'
        THROW 55000, 'Invalid customer username', 1;
    IF @email IS NULL OR LEN(@email) NOT BETWEEN 5 AND 100
       OR @email NOT LIKE '_%@_%._%'
       OR @email LIKE '% %'
       OR @email COLLATE Latin1_General_BIN2 LIKE '%[^A-Za-z0-9@._+%-]%'
        THROW 55000, 'Invalid customer email', 1;
    IF @password_hash IS NULL OR DATALENGTH(@password_hash) <> 60
       OR LEFT(@password_hash, 4) NOT IN ('$2a$', '$2b$', '$2y$')
        THROW 55000, 'Invalid password hash', 1;
    INSERT dbo.Users(username, email, password_hash)
        OUTPUT inserted.user_id AS identity_id
        VALUES (@username, @email, @password_hash);
END;
GO
GRANT EXECUTE ON app.RegisterCustomer TO app_runtime;
GO
