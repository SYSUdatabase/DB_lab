-- Week 6 backup/restore (SQLCMD mode, approved copy-only operation).
-- Only TokenHubDB_v01_A is read for backup; target is a DISTINCT NEW database.
-- Run with sqlcmd -S localhost\SQLEXPRESS -d master -E -C -b -i week6/prepare_copy.sql.
:on error exit
SET NOCOUNT ON;
IF DB_ID(N'TokenHubDB_v01_A') IS NULL THROW 51010, 'Source v0.1 missing', 1;
IF DB_ID(N'TokenHubDB_v10_W6_20261014') IS NOT NULL THROW 51011, 'Target database already exists; refusing overwrite', 1;
GO
BACKUP DATABASE [TokenHubDB_v01_A]
TO DISK = N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\TokenHubDB_v01_A_W6_20261014.bak'
WITH COPY_ONLY, CHECKSUM, STATS = 10;
GO
RESTORE VERIFYONLY
FROM DISK = N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\TokenHubDB_v01_A_W6_20261014.bak'
WITH CHECKSUM;
GO
RESTORE DATABASE [TokenHubDB_v10_W6_20261014]
FROM DISK = N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup\TokenHubDB_v01_A_W6_20261014.bak'
WITH MOVE N'TokenHubDB_v01_A' TO N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\TokenHubDB_v10_W6_20261014.mdf',
     MOVE N'TokenHubDB_v01_A_log' TO N'D:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA\TokenHubDB_v10_W6_20261014_log.ldf',
     RECOVERY, CHECKSUM, STATS = 10;
GO
IF DB_ID(N'TokenHubDB_v10_W6_20261014') IS NULL THROW 51012, 'Restore failed', 1;
PRINT N'W6_SOURCE_PROTECTED_TARGET_CREATED';
GO
