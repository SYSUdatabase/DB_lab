:on error exit
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON;
SET ANSI_PADDING ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]Web%' OR DB_NAME()<>N'$(DatabaseName)'
 THROW 56000,'Week10 requires an isolated v11 Web database',1;
IF SCHEMA_ID('app') IS NULL OR OBJECT_ID('app.Execute','P') IS NULL
 OR OBJECT_ID('dbo.OrderTokenLots','U') IS NULL OR OBJECT_ID('dbo.trg_W5_NoEditFinalizedDetails','TR') IS NULL
 THROW 56000,'Complete v11 and Web installation required',1;
IF SCHEMA_ID('w10') IS NOT NULL THROW 56009,'Week10 already installed',1;
BEGIN TRANSACTION;
GO
:r sql/week10/schema.sql
:r sql/week10/function.sql
:r sql/week10/procedure.sql
:r sql/week10/app_adapters.sql
:r sql/app/week10.sql
COMMIT TRANSACTION;
GO
