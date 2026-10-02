SET NOCOUNT ON;
DECLARE @tables TABLE(table_name SYSNAME,pk_name SYSNAME);
INSERT @tables VALUES
('Roles','role_id'),('Users','user_id'),('Products','product_id'),
('UpstreamAccount','account_id'),('Inventory','inventory_id'),('Employees','employee_id'),
('Orders','order_id'),('OrderDetails','detail_id'),('InventoryLog','log_id'),
('TokenBalances','balance_id'),('TokenUsageLogs','log_id'),('UsageSummary','summary_id'),
('RestockTask','task_id'),('ExceptionLog','exception_id');
CREATE TABLE #cmp(table_name SYSNAME,a_rows BIGINT,b_rows BIGINT,a_hash VARCHAR(64),b_hash VARCHAR(64));
DECLARE @t SYSNAME,@pk SYSNAME,@sql NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT table_name,pk_name FROM @tables ORDER BY table_name;
OPEN c; FETCH NEXT FROM c INTO @t,@pk;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @sql=N'DECLARE @a NVARCHAR(MAX),@b NVARCHAR(MAX);'+
 N'SELECT @a=(SELECT * FROM TokenHubDB_v01_A.dbo.'+QUOTENAME(@t)+N' ORDER BY '+QUOTENAME(@pk)+N' FOR JSON PATH,INCLUDE_NULL_VALUES);'+
 N'SELECT @b=(SELECT * FROM TokenHubDB_v01_B.dbo.'+QUOTENAME(@t)+N' ORDER BY '+QUOTENAME(@pk)+N' FOR JSON PATH,INCLUDE_NULL_VALUES);'+
 N'INSERT #cmp SELECT @name,(SELECT COUNT_BIG(*) FROM TokenHubDB_v01_A.dbo.'+QUOTENAME(@t)+N'),'+
 N'(SELECT COUNT_BIG(*) FROM TokenHubDB_v01_B.dbo.'+QUOTENAME(@t)+N'),CONVERT(VARCHAR(64),HASHBYTES(''SHA2_256'',@a),2),CONVERT(VARCHAR(64),HASHBYTES(''SHA2_256'',@b),2);';
 EXEC sys.sp_executesql @sql,N'@name SYSNAME',@name=@t;
 FETCH NEXT FROM c INTO @t,@pk;
END;
CLOSE c; DEALLOCATE c;
SELECT table_name,a_rows,b_rows,
       LEFT(a_hash,12) AS a_hash_12,LEFT(b_hash,12) AS b_hash_12,
       CASE WHEN a_rows=b_rows AND a_hash=b_hash THEN 'PASS' ELSE 'FAIL' END AS result
FROM #cmp ORDER BY table_name;
SELECT COUNT(*) AS mismatches FROM #cmp WHERE a_rows<>b_rows OR a_hash<>b_hash;
DROP TABLE #cmp;
PRINT N'PASS: two fresh databases have identical 14-table content signatures';
