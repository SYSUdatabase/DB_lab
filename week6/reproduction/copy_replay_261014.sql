-- Week 6 replay stage 2: isolated backup/restore of a clean v0.1 built
-- FROM THE PRE-WEEK6 CODE ZIP (not from TokenHubDB_v01_A).
:on error exit
SET NOCOUNT ON;
IF DB_ID('TokenHubDB_v01_W6Replay261014') IS NULL THROW 52200,'Rebuilt source missing',1;
IF DB_ID('TokenHubDB_v10_W6Replay261014') IS NOT NULL THROW 52201,'Replay target exists',1;
GO
BACKUP DATABASE [TokenHubDB_v01_W6Replay261014] TO DISK =
 N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\TokenHubDB_v01_W6Replay261014_CopyOnly.bak'
 WITH COPY_ONLY,CHECKSUM,STATS=10;
GO
RESTORE VERIFYONLY FROM DISK =
 N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\TokenHubDB_v01_W6Replay261014_CopyOnly.bak'
 WITH CHECKSUM;
GO
RESTORE DATABASE [TokenHubDB_v10_W6Replay261014] FROM DISK =
 N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\TokenHubDB_v01_W6Replay261014_CopyOnly.bak'
 WITH MOVE N'TokenHubDB_v01_W6Replay261014' TO N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\TokenHubDB_v10_W6Replay261014.mdf',
 MOVE N'TokenHubDB_v01_W6Replay261014_log' TO N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\TokenHubDB_v10_W6Replay261014_log.ldf',
 CHECKSUM, RECOVERY, STATS=10;
GO
IF DB_ID('TokenHubDB_v10_W6Replay261014') IS NULL THROW 52202,'Replay restore failed',1;
PRINT 'PASS independent clean v0.1 copy restored for week6 migration';
GO