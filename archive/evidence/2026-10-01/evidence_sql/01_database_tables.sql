SET NOCOUNT ON;
SELECT DB_NAME() AS database_name,
       COUNT(*) AS business_tables
FROM sys.tables WHERE is_ms_shipped=0;

SELECT t.name AS table_name,
       SUM(p.rows) AS row_count
FROM sys.tables t
JOIN sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1)
WHERE t.is_ms_shipped=0
GROUP BY t.name
ORDER BY t.name;

SELECT (SELECT COUNT(*) FROM sys.views WHERE is_ms_shipped=0) AS views,
       (SELECT COUNT(*) FROM sys.database_principals WHERE type='R' AND name LIKE 'hub_%') AS db_roles,
       (SELECT COUNT(*) FROM sys.database_principals WHERE type='S' AND name LIKE 'hub_%') AS demo_users;
