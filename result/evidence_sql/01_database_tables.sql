USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>14
 OR (SELECT COUNT(*) FROM sys.views WHERE is_ms_shipped=0)<>10
 THROW 51460,N'Object counts mismatch',1;
SELECT DB_NAME() AS database_name;
SELECT name FROM sys.tables WHERE is_ms_shipped=0 ORDER BY name;
SELECT (SELECT COUNT(*) FROM sys.views WHERE is_ms_shipped=0) AS views_count;
PRINT N'PASS database, 14 tables and 10 views';
