SET NOCOUNT ON;
PRINT N'A/B/C three-database signature comparison (14 base tables)';
GO
DECLARE @t SYSNAME,@pk SYSNAME,@stmt NVARCHAR(MAX);
CREATE TABLE #expected(table_name SYSNAME,pk_name SYSNAME);
INSERT #expected VALUES
('Roles','role_id'),('Users','user_id'),('Products','product_id'),
('UpstreamAccount','account_id'),('Inventory','inventory_id'),
('Employees','employee_id'),('Orders','order_id'),('OrderDetails','detail_id'),
('InventoryLog','log_id'),('TokenBalances','balance_id'),('TokenUsageLogs','log_id'),
('UsageSummary','summary_id'),('RestockTask','task_id'),('ExceptionLog','exception_id');

CREATE TABLE #sig(db_name SYSNAME,table_name SYSNAME,rows_count BIGINT,sha256 VARCHAR(64));

DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT table_name,pk_name FROM #expected ORDER BY table_name;
OPEN table_cursor;
FETCH NEXT FROM table_cursor INTO @t,@pk;
WHILE @@FETCH_STATUS=0
BEGIN
  SET @stmt=N'
    INSERT #sig(db_name,table_name,rows_count,sha256)
    SELECT N''A'',@t,(SELECT COUNT_BIG(*) FROM [TokenHubDB_v01_A].dbo.'+QUOTENAME(@t)+N'),'
    +N'(SELECT CONVERT(VARCHAR(64),HASHBYTES(''SHA2_256'',(SELECT * FROM [TokenHubDB_v01_A].dbo.'+QUOTENAME(@t)
    +N' ORDER BY '+QUOTENAME(@pk)+N' FOR JSON PATH,INCLUDE_NULL_VALUES)),2))'
    +N' UNION ALL SELECT N''B'',@t,(SELECT COUNT_BIG(*) FROM [TokenHubDB_v01_B].dbo.'+QUOTENAME(@t)+N'),'
    +N'(SELECT CONVERT(VARCHAR(64),HASHBYTES(''SHA2_256'',(SELECT * FROM [TokenHubDB_v01_B].dbo.'+QUOTENAME(@t)
    +N' ORDER BY '+QUOTENAME(@pk)+N' FOR JSON PATH,INCLUDE_NULL_VALUES)),2))'
    +N' UNION ALL SELECT N''C'',@t,(SELECT COUNT_BIG(*) FROM [TokenHubDB_v01_C].dbo.'+QUOTENAME(@t)+N'),'
    +N'(SELECT CONVERT(VARCHAR(64),HASHBYTES(''SHA2_256'',(SELECT * FROM [TokenHubDB_v01_C].dbo.'+QUOTENAME(@t)
    +N' ORDER BY '+QUOTENAME(@pk)+N' FOR JSON PATH,INCLUDE_NULL_VALUES)),2));';
  EXEC sys.sp_executesql @stmt,N'@t SYSNAME',@t=@t;
  FETCH NEXT FROM table_cursor INTO @t,@pk;
END;
CLOSE table_cursor;
DEALLOCATE table_cursor;

SELECT a.table_name,a.rows_count AS rows_A,a.sha256 AS sha_A,
       b.sha256 AS sha_B,c.sha256 AS sha_C,
       CASE WHEN b.sha256=a.sha256 AND c.sha256=a.sha256 THEN 'MATCH' ELSE 'DIFF' END AS result
FROM #sig a
JOIN #sig b ON b.table_name=a.table_name AND b.db_name='B'
JOIN #sig c ON c.table_name=a.table_name AND c.db_name='C'
WHERE a.db_name='A'
ORDER BY a.table_name;

SELECT COUNT(*) AS tables_compared,
       SUM(CASE WHEN b.sha256=a.sha256 AND c.sha256=a.sha256 THEN 1 ELSE 0 END) AS tables_matching
FROM #sig a
JOIN #sig b ON b.table_name=a.table_name AND b.db_name='B'
JOIN #sig c ON c.table_name=a.table_name AND c.db_name='C'
WHERE a.db_name='A';

DROP TABLE #sig;
DROP TABLE #expected;
GO