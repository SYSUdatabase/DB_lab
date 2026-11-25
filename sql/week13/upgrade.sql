-- 已按旧版准备的专用 WebW13 实验库可重放此增量；不用于已有共享库。
:on error exit
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON;
SET ANSI_PADDING ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME()<>N'$(DatabaseName)' OR DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]WebW13%'
 OR SCHEMA_ID('w12') IS NULL THROW 57116,'Use a dedicated Week 13 batch',1;
BEGIN TRAN;
GO
:r sql/week13/provider_lock.sql
:r sql/week12/order_transaction.sql
:r sql/week12/restock_transaction.sql
COMMIT;
GO
