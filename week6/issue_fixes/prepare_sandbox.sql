-- Isolated copy for W5 issue remediation; NO SOURCE writes.
:on error exit
SET NOCOUNT ON;
IF DB_ID(N'TokenHubDB_v10_W6_20261014') IS NULL
 THROW 51900,'Source v1.0 missing',1;
IF DB_ID(N'TokenHubDB_v11_Issues_20261014') IS NOT NULL
 THROW 51901,'Remediation target already exists; refuse overwrite',1;
GO
BACKUP DATABASE [TokenHubDB_v10_W6_20261014]
TO DISK=N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\TokenHubDB_v10_W6_IssuesSeed_20261014.bak'
WITH COPY_ONLY,CHECKSUM,STATS=10;
GO
RESTORE VERIFYONLY FROM DISK=N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\TokenHubDB_v10_W6_IssuesSeed_20261014.bak' WITH CHECKSUM;
GO
RESTORE DATABASE [TokenHubDB_v11_Issues_20261014]
FROM DISK=N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\TokenHubDB_v10_W6_IssuesSeed_20261014.bak'
WITH MOVE N'TokenHubDB_v01_A' TO N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\TokenHubDB_v11_Issues_20261014.mdf',
MOVE N'TokenHubDB_v01_A_log' TO N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\TokenHubDB_v11_Issues_20261014_log.ldf',
RECOVERY,CHECKSUM,STATS=10;
GO
IF DB_ID(N'TokenHubDB_v11_Issues_20261014') IS NULL THROW 51902,'Restore failed',1;
PRINT N'PASS independent v1.1 remediation sandbox created';
GO