-- A、B 各执行一次；先确认连接同一个专用库且 SPID 不同。
IF DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]WebW13%' OR SCHEMA_ID('w13lab') IS NULL OR @@TRANCOUNT<>0
 THROW 57104,'Open a clean session in the initialized Week 13 database',1;
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_WARNINGS ON;
SET ANSI_PADDING ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET LOCK_TIMEOUT 90000;
SET DEADLOCK_PRIORITY NORMAL;
SELECT @@SPID spid,DB_NAME() database_name,SERVERPROPERTY('ProductVersion') version,
 s.transaction_isolation_level,d.is_read_committed_snapshot_on
FROM sys.dm_exec_sessions s CROSS JOIN sys.databases d
WHERE s.session_id=@@SPID AND d.database_id=DB_ID();
