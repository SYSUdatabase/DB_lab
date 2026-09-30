SET NOCOUNT ON;
DECLARE @expected TABLE(table_name SYSNAME,pk_name SYSNAME);
INSERT @expected VALUES
('Roles','role_id'),('Users','user_id'),('Products','product_id'),
('UpstreamAccount','account_id'),('Inventory','inventory_id'),
('Employees','employee_id'),('Orders','order_id'),('OrderDetails','detail_id'),
('InventoryLog','log_id'),('TokenBalances','balance_id'),('TokenUsageLogs','log_id'),
('UsageSummary','summary_id'),('RestockTask','task_id'),('ExceptionLog','exception_id');
DECLARE @t SYSNAME,@pk SYSNAME,@stmt NVARCHAR(MAX);
CREATE TABLE #Signatures(table_name SYSNAME,rows_count BIGINT,sha256 VARCHAR(64));
DECLARE signatures CURSOR LOCAL FAST_FORWARD FOR
SELECT table_name,pk_name FROM @expected ORDER BY table_name;
OPEN signatures;
FETCH NEXT FROM signatures INTO @t,@pk;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @stmt=N'DECLARE @j NVARCHAR(MAX); SELECT @j=(SELECT * FROM dbo.'+
      QUOTENAME(@t)+N' ORDER BY '+QUOTENAME(@pk)+
      N' FOR JSON PATH,INCLUDE_NULL_VALUES); INSERT #Signatures
      SELECT @name,COUNT_BIG(*),CONVERT(VARCHAR(64),HASHBYTES(''SHA2_256'',@j),2)
      FROM dbo.'+QUOTENAME(@t)+N';';
    EXEC sys.sp_executesql @stmt,N'@name SYSNAME',@name=@t;
    FETCH NEXT FROM signatures INTO @t,@pk;
END;
CLOSE signatures;
DEALLOCATE signatures;
SELECT CONCAT(table_name,'|',rows_count,'|',sha256)
FROM #Signatures ORDER BY table_name;
DROP TABLE #Signatures;
