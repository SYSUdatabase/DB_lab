-- Week 3 / 00_create_database.sql
-- Target: SQL Server 2025 Express, localhost\SQLEXPRESS
-- This script never drops an existing database automatically.

USE [master];
GO

IF DB_ID(N'$(DatabaseName)') IS NULL
BEGIN
    CREATE DATABASE [$(DatabaseName)]
        COLLATE Chinese_PRC_90_CI_AI_SC_UTF8;
END
ELSE
BEGIN
    THROW 50001, N'$(DatabaseName) already exists. Reproduction requires an empty database.', 1;
END;
GO

ALTER DATABASE [$(DatabaseName)] SET RECOVERY SIMPLE;
GO
