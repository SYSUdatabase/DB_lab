-- Week 6 migration regression. Only intended to run on isolated v1.0 copy.
-- Reads source v0.1 for comparison; writes solely inside rollback transactions.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF DB_NAME()<>N'TokenHubDB_v10_W6_20261014'
 THROW 51700, 'Wrong regression target database', 1;
IF OBJECT_ID(N'dbo.UsageSummary',N'V') IS NULL
 OR OBJECT_ID(N'dbo.UsageSummaryCore',N'U') IS NULL
 OR OBJECT_ID(N'dbo.UsagePeriod',N'U') IS NULL
 THROW 51701, 'Normalization target objects missing', 1;

PRINT 'R01 schema and constraint trust';
IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>15
 OR (SELECT COUNT(*) FROM sys.views WHERE is_ms_shipped=0)<>11
 OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled=0 AND is_not_trusted=0)<>18
 OR EXISTS(SELECT 1 FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1)
 OR EXISTS(SELECT 1 FROM sys.check_constraints WHERE is_disabled=1 OR is_not_trusted=1)
 OR NOT EXISTS(SELECT 1 FROM sys.foreign_keys WHERE name=N'FK_UsageSummaryCore_UsagePeriod')
 THROW 51702,'Counts or untrusted constraints',1;
IF (SELECT COUNT_BIG(*) FROM dbo.UsageSummaryCore)<>3394
 OR (SELECT COUNT_BIG(*) FROM dbo.UsageSummary)<>3394
 OR (SELECT COUNT(*) FROM dbo.UsagePeriod)<>99
 OR (SELECT COUNT(*) FROM dbo.v_CustomerService)<>40
 THROW 51703,'Migrated row counts or missing official view',1;
IF COL_LENGTH('dbo.UsageSummaryCore','period_end') IS NOT NULL
 OR COL_LENGTH('dbo.UsagePeriod','period_end') IS NULL
 THROW 51704,'period_end not moved to parent table',1;
PRINT 'PASS R01 target schema 15 tables 18 FK 11 views';

PRINT 'R02 lossless join and source comparison';
IF EXISTS (
 SELECT summary_id,user_id,product_id,period_type,period_start,period_end,
        total_tokens_used,total_upstream_consumed,request_count,last_updated_at
 FROM TokenHubDB_v01_A.dbo.UsageSummary
 EXCEPT
 SELECT summary_id,user_id,product_id,period_type,period_start,period_end,
        total_tokens_used,total_upstream_consumed,request_count,last_updated_at
 FROM dbo.UsageSummary
) OR EXISTS (
 SELECT summary_id,user_id,product_id,period_type,period_start,period_end,
        total_tokens_used,total_upstream_consumed,request_count,last_updated_at
 FROM dbo.UsageSummary
 EXCEPT
 SELECT summary_id,user_id,product_id,period_type,period_start,period_end,
        total_tokens_used,total_upstream_consumed,request_count,last_updated_at
 FROM TokenHubDB_v01_A.dbo.UsageSummary
) THROW 51705,'Lossless reconstructed UsageSummary differs from v0.1',1;
IF EXISTS (
 SELECT 1 FROM dbo.UsageSummaryCore c
 LEFT JOIN dbo.UsagePeriod p ON p.period_type=c.period_type AND p.period_start=c.period_start
 WHERE p.period_type IS NULL
) THROW 51706,'Orphan normalized summary',1;
PRINT 'PASS R02 reconstructed summary identical to source both EXCEPT directions';

PRINT 'R03 order details, paid product sales, inventory, balances, usage';
IF EXISTS (SELECT * FROM dbo.OrderDetails EXCEPT SELECT * FROM TokenHubDB_v01_A.dbo.OrderDetails)
 OR EXISTS (SELECT * FROM TokenHubDB_v01_A.dbo.OrderDetails EXCEPT SELECT * FROM dbo.OrderDetails)
 OR EXISTS (SELECT * FROM dbo.Orders EXCEPT SELECT * FROM TokenHubDB_v01_A.dbo.Orders)
 OR EXISTS (SELECT * FROM TokenHubDB_v01_A.dbo.Orders EXCEPT SELECT * FROM dbo.Orders)
 OR EXISTS (SELECT * FROM dbo.v_ProductSales EXCEPT SELECT * FROM TokenHubDB_v01_A.dbo.v_ProductSales)
 OR EXISTS (SELECT * FROM TokenHubDB_v01_A.dbo.v_ProductSales EXCEPT SELECT * FROM dbo.v_ProductSales)
 OR EXISTS (SELECT * FROM dbo.Inventory EXCEPT SELECT * FROM TokenHubDB_v01_A.dbo.Inventory)
 OR EXISTS (SELECT * FROM TokenHubDB_v01_A.dbo.Inventory EXCEPT SELECT * FROM dbo.Inventory)
 OR EXISTS (SELECT * FROM dbo.TokenBalances EXCEPT SELECT * FROM TokenHubDB_v01_A.dbo.TokenBalances)
 OR EXISTS (SELECT * FROM TokenHubDB_v01_A.dbo.TokenBalances EXCEPT SELECT * FROM dbo.TokenBalances)
 OR EXISTS (SELECT * FROM dbo.TokenUsageLogs EXCEPT SELECT * FROM TokenHubDB_v01_A.dbo.TokenUsageLogs)
 OR EXISTS (SELECT * FROM TokenHubDB_v01_A.dbo.TokenUsageLogs EXCEPT SELECT * FROM dbo.TokenUsageLogs)
 THROW 51707,'Unrelated business semantics differ from source',1;
PRINT 'PASS R03 source order, sales, inventory, balance and usage sets unchanged';

PRINT 'R04 period functional dependency is enforced';
IF EXISTS (
 SELECT 1 FROM dbo.UsagePeriod
 WHERE (period_type='daily' AND period_end<>period_start)
 OR (period_type='weekly' AND
        (period_end<>DATEADD(DAY,6,period_start)
         OR (DATEDIFF(DAY,CONVERT(date,'19000101'),period_start)%7)<>0))
 OR (period_type='monthly' AND
        (DAY(period_start)<>1 OR period_end<>EOMONTH(period_start)))
) THROW 51708, 'Period mapping invalid', 1;
PRINT 'PASS R04 fixed period boundaries enforced';

PRINT 'R05 legal insert path in transaction (rollback)';
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.UsagePeriod(period_type,period_start,period_end)
 VALUES ('monthly','2027-01-01','2027-01-31');
 INSERT dbo.UsageSummaryCore(user_id,product_id,period_type,period_start,
        total_tokens_used,total_upstream_consumed,request_count,last_updated_at)
 VALUES (1,1,'monthly','2027-01-01',12,16,1,'2027-01-31');
 DECLARE @new_id INT=SCOPE_IDENTITY();
 IF NOT EXISTS(SELECT 1 FROM dbo.UsageSummary
   WHERE summary_id=@new_id AND period_end='2027-01-31'
      AND total_tokens_used=12)
    THROW 51709,'Valid inserted row not visible via compatibility view',1;
 ROLLBACK TRAN;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRAN;
 THROW;
END CATCH;
IF EXISTS(SELECT 1 FROM dbo.UsagePeriod WHERE period_start='2027-01-01')
 THROW 51710,'Rollback of legal write failed',1;
PRINT 'PASS R05 legal normalized insert and rollback';

PRINT 'R06 duplicate period candidate key must fail';
DECLARE @caught INT=0;
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.UsagePeriod(period_type,period_start,period_end)
 SELECT TOP(1) period_type,period_start,period_end FROM dbo.UsagePeriod ORDER BY period_start;
 ROLLBACK TRAN;
END TRY
BEGIN CATCH
 SET @caught=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK TRAN;
END CATCH;
IF @caught NOT IN (2627,2601) THROW 51711,'Duplicate period not rejected as unique violation',1;
PRINT 'PASS R06 duplicate period rejected (2601/2627)';

PRINT 'R07 invalid weekly boundary must fail CHECK';
SET @caught=0;
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.UsagePeriod(period_type,period_start,period_end)
 VALUES ('weekly','2027-01-05','2027-01-11');
 ROLLBACK TRAN;
END TRY
BEGIN CATCH
 SET @caught=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK TRAN;
END CATCH;
IF @caught<>547 THROW 51712,'Invalid weekly boundary did not fail CHECK 547',1;
PRINT 'PASS R07 invalid weekly period rejected (547)';

PRINT 'R08 orphan period FK must fail';
SET @caught=0;
BEGIN TRY
 BEGIN TRAN;
 INSERT dbo.UsageSummaryCore(user_id,product_id,period_type,period_start,
        total_tokens_used,total_upstream_consumed,request_count,last_updated_at)
 VALUES (1,1,'monthly','2033-01-01',0,0,0,'2033-01-01');
 ROLLBACK TRAN;
END TRY
BEGIN CATCH
 SET @caught=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK TRAN;
END CATCH;
IF @caught<>547 THROW 51713,'Missing period parent not rejected FK 547',1;
PRINT 'PASS R08 missing period FK rejected (547)';

PRINT 'R09 permission matrix for new objects';
IF EXISTS (
 SELECT 1 FROM sys.tables t CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE')) p(name)
 WHERE t.is_ms_shipped=0 AND NOT EXISTS(
    SELECT 1 FROM sys.database_permissions d
    WHERE d.grantee_principal_id=DATABASE_PRINCIPAL_ID('hub_manager')
      AND d.class=1 AND d.major_id=t.object_id AND d.minor_id=0
      AND d.state IN ('G','W') AND d.permission_name=p.name
 )
) THROW 51714,'Manager CRUD grants not complete on 15 tables',1;
IF EXISTS (
 SELECT 1 FROM sys.database_permissions d
 JOIN sys.database_principals p ON d.grantee_principal_id=p.principal_id
 WHERE p.name IN ('public','hub_staff','hub_customer','hub_guest')
   AND d.class=1 AND d.major_id IN (
      OBJECT_ID('dbo.UsagePeriod'),OBJECT_ID('dbo.UsageSummaryCore'),
      OBJECT_ID('dbo.UsageSummary'))
   AND d.permission_name IN ('SELECT','INSERT','UPDATE','DELETE','CONTROL')
   AND d.state IN ('G','W')
) THROW 51715,'Non-manager gained access to new period/summary objects',1;
IF NOT EXISTS (SELECT 1 FROM sys.database_permissions
 WHERE grantee_principal_id=DATABASE_PRINCIPAL_ID('hub_staff')
   AND major_id=OBJECT_ID('dbo.v_CustomerService')
   AND permission_name='SELECT' AND state IN ('G','W'))
 THROW 51716,'Staff expected customer service read grant missing',1;
PRINT 'PASS R09 least privilege and manager CRUD grants';

PRINT 'R10 positive role context: manager and staff approved read views';
DECLARE @base_user SYSNAME=USER_NAME();
BEGIN TRY
 EXECUTE AS USER='hub_manager_demo';
 EXEC(N'IF (SELECT COUNT(*) FROM dbo.UsagePeriod)<>99 OR
  (SELECT COUNT(*) FROM dbo.UsageSummary)<>3394 THROW 51717,''Manager cannot view periods'',1;');
 REVERT;
 EXECUTE AS USER='hub_staff_demo';
 EXEC(N'IF (SELECT COUNT(*) FROM dbo.v_CustomerService)<>40
 THROW 51718,''Staff customer-service view invalid'',1;');
 REVERT;
END TRY
BEGIN CATCH
 IF USER_NAME()<>@base_user REVERT;
 THROW;
END CATCH;
PRINT 'PASS R10 manager and staff approved read access';

PRINT 'R11 negative role context: staff/customer/guest blocked';
DECLARE @who SYSNAME,@stmt NVARCHAR(MAX);
DECLARE denied CURSOR LOCAL FAST_FORWARD FOR SELECT actor,sqltext FROM (VALUES
  (N'hub_staff_demo',N'SELECT COUNT(*) FROM dbo.UsagePeriod'),
  (N'hub_user_1',N'SELECT COUNT(*) FROM dbo.UsageSummary'),
  (N'hub_guest_demo',N'SELECT COUNT(*) FROM dbo.UsagePeriod')
) d(actor,sqltext);
OPEN denied;
FETCH NEXT FROM denied INTO @who,@stmt;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @caught=0;
 BEGIN TRY
  EXECUTE AS USER=@who;
  EXEC sys.sp_executesql @stmt;
  REVERT;
 END TRY
 BEGIN CATCH
  SET @caught=ERROR_NUMBER();
  IF USER_NAME()<>@base_user REVERT;
 END CATCH;
 IF @caught<>229 THROW 51719,'Role could read forbidden object or wrong error',1;
 FETCH NEXT FROM denied INTO @who,@stmt;
END;
CLOSE denied;
DEALLOCATE denied;
IF USER_NAME()<>@base_user OR @@TRANCOUNT<>0
 THROW 51720,'Execution context or transaction not restored',1;
PRINT 'PASS R11 staff/customer/guest appropriately denied with 229';

PRINT 'R12 original source database remains untouched';
IF OBJECT_ID(N'TokenHubDB_v01_A.dbo.UsagePeriod',N'U') IS NOT NULL
 OR (SELECT COUNT(*) FROM TokenHubDB_v01_A.sys.tables WHERE is_ms_shipped=0)<>14
 OR (SELECT COUNT(*) FROM TokenHubDB_v01_A.sys.views WHERE is_ms_shipped=0)<>9
 THROW 51721,'Source baseline schema changed',1;
IF (SELECT COUNT_BIG(*) FROM TokenHubDB_v01_A.dbo.UsageSummary)<>3394
 THROW 51722,'Source summary count changed',1;
IF (SELECT COUNT_BIG(*) FROM dbo.UsageSummary)<>3394
 THROW 51723,'Test rollback failed',1;
PRINT 'PASS R12 source v0.1 and target business row counts unchanged';
PRINT 'PASS W6 REGRESSION R01-R12';
