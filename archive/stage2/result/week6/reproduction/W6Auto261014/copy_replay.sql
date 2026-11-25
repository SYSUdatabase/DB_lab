:on error exit
SET NOCOUNT ON;
IF DB_ID(N'TokenHubDB_v01_W6Auto261014') IS NULL OR DB_ID(N'TokenHubDB_v10_W6Auto261014') IS NOT NULL
 THROW 52300,'Invalid or occupied replay database',1;
GO
BACKUP DATABASE [TokenHubDB_v01_W6Auto261014] TO DISK=N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\TokenHubDB_v01_W6Auto261014_w6_replay.bak'
 WITH COPY_ONLY,CHECKSUM,STATS=10;
GO
RESTORE VERIFYONLY FROM DISK=N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\TokenHubDB_v01_W6Auto261014_w6_replay.bak' WITH CHECKSUM;
GO
RESTORE DATABASE [TokenHubDB_v10_W6Auto261014] FROM DISK=N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\TokenHubDB_v01_W6Auto261014_w6_replay.bak'
 WITH MOVE N'TokenHubDB_v01_W6Auto261014' TO N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\TokenHubDB_v10_W6Auto261014.mdf',
 MOVE N'TokenHubDB_v01_W6Auto261014_log' TO N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\TokenHubDB_v10_W6Auto261014_log.ldf',
 RECOVERY,CHECKSUM,STATS=10;
GO
IF DB_ID(N'TokenHubDB_v10_W6Auto261014') IS NULL THROW 52301,'Replay restore missing',1;
PRINT 'PASS new v0.1 replay database safely restored';
GO