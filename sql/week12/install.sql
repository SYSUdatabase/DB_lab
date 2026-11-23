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
 THROW 57000,'Week12 requires an isolated v11 Web database',1;
IF SCHEMA_ID('w11') IS NULL OR OBJECT_ID('dbo.trg_W11_OrderCompletionRules','TR') IS NULL
 THROW 57000,'Week11 extension must be installed first',1;
IF SCHEMA_ID('w12') IS NOT NULL THROW 57009,'Week12 already installed',1;
BEGIN TRANSACTION;
GO
:r sql/week12/category.sql
:r sql/week12/order_transaction.sql
:r sql/week12/restock_transaction.sql
COMMIT TRANSACTION;
GO
