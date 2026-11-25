-- Week 6 v1.0 migration: isolate recurring period end dates.
-- EXECUTE ONLY against restored copy TokenHubDB_v10_W6Auto261014.
-- NOT SAFE to run on TokenHubDB_v01_A. Never use run_v01.ps1 -DropExisting.
-- Single transaction; any failure rolls back. Prior source backup verified in P0.
-- Existing reads against dbo.UsageSummary continue through a compatibility view;
-- writes must target dbo.UsageSummaryCore and dbo.UsagePeriod explicitly.
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF DB_NAME() <> N'TokenHubDB_v10_W6Auto261014'
    THROW 51600, 'W6 migration refused: database name must match isolated target', 1;
IF OBJECT_ID(N'dbo.UsageSummary',N'U') IS NULL
    OR OBJECT_ID(N'dbo.UsageSummaryCore',N'U') IS NOT NULL
    OR OBJECT_ID(N'dbo.UsagePeriod',N'U') IS NOT NULL
    OR OBJECT_ID(N'dbo.UsageSummary',N'V') IS NOT NULL
    THROW 51601, 'W6 migration refused: target already changed or incorrect schema', 1;
IF COL_LENGTH(N'dbo.UsageSummary',N'period_end') IS NULL
    OR (SELECT COUNT_BIG(*) FROM dbo.UsageSummary) <> 3394
    OR (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0) <> 14
    OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled=0 AND is_not_trusted=0) <> 17
    THROW 51602, 'W6 migration refused: source structure/count/FK precondition failed', 1;
IF EXISTS (
 SELECT 1 FROM dbo.UsageSummary
 GROUP BY period_type, period_start HAVING COUNT(DISTINCT period_end)>1
) THROW 51603, 'Conflicting period_end for one period key: manual resolution required', 1;
IF EXISTS (
 SELECT 1 FROM dbo.UsageSummary
 WHERE (period_type='daily' AND period_end<>period_start)
    OR (period_type='weekly' AND
        (period_end<>DATEADD(DAY,6,period_start)
         OR (DATEDIFF(DAY,CONVERT(date,'19000101'),period_start)%7)<>0))
    OR (period_type='monthly' AND
        (DAY(period_start)<>1 OR period_end<>EOMONTH(period_start)))
    OR period_type NOT IN ('daily','weekly','monthly')
) THROW 51604, 'Period boundaries do not follow fixed day/Monday-week/calendar-month rules', 1;
IF EXISTS(SELECT 1 FROM sys.check_constraints WHERE is_disabled=1 OR is_not_trusted=1)
 OR EXISTS(SELECT 1 FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1)
 THROW 51605, 'Source constraint is not enabled and trusted', 1;
IF DATABASE_PRINCIPAL_ID(N'hub_manager') IS NULL
 THROW 51606, 'Manager role missing', 1;
-- Support two measured v0.1 baseline states, without changing the data:
-- 9 views, missing documented v_CustomerService (historical local v0.1_A);
-- 10 views, including v_CustomerService (fresh build from pre-week6 code).
-- Any other view count/name combination must stop before writing.
DECLARE @source_view_count INT =
 (SELECT COUNT(*) FROM sys.views WHERE is_ms_shipped=0);
IF @source_view_count NOT IN (9,10)
 OR (@source_view_count=9 AND OBJECT_ID(N'dbo.v_CustomerService',N'V') IS NOT NULL)
 OR (@source_view_count=10 AND OBJECT_ID(N'dbo.v_CustomerService',N'V') IS NULL)
 THROW 51612, 'Unexpected source views; review baseline before migration', 1;

BEGIN TRY
 BEGIN TRANSACTION;
 CREATE TABLE dbo.UsagePeriod (
   period_type VARCHAR(10) NOT NULL,
   period_start DATE NOT NULL,
   period_end DATE NOT NULL,
   CONSTRAINT PK_UsagePeriod PRIMARY KEY (period_type, period_start),
   CONSTRAINT CK_UsagePeriod_type CHECK (period_type IN ('daily','weekly','monthly')),
   CONSTRAINT CK_UsagePeriod_dates CHECK (
        (period_type='daily' AND period_end=period_start)
     OR (period_type='weekly' AND period_end=DATEADD(DAY,6,period_start)
         AND (DATEDIFF(DAY,CONVERT(date,'19000101'),period_start)%7)=0)
     OR (period_type='monthly' AND DAY(period_start)=1
         AND period_end=EOMONTH(period_start))
   )
 );
 INSERT dbo.UsagePeriod(period_type,period_start,period_end)
 SELECT period_type,period_start,MIN(period_end)
 FROM dbo.UsageSummary GROUP BY period_type,period_start;
 IF (SELECT COUNT(*) FROM dbo.UsagePeriod)<>99
  THROW 51607, 'Unexpected number of distinct periods', 1;
 ALTER TABLE dbo.UsageSummary DROP CONSTRAINT CK_UsageSummary_dates;
 EXEC sys.sp_rename N'dbo.UsageSummary',N'UsageSummaryCore',N'OBJECT';
 ALTER TABLE dbo.UsageSummaryCore DROP COLUMN period_end;
 ALTER TABLE dbo.UsageSummaryCore WITH CHECK
 ADD CONSTRAINT FK_UsageSummaryCore_UsagePeriod FOREIGN KEY(period_type,period_start)
 REFERENCES dbo.UsagePeriod(period_type,period_start);
 -- All original columns are exposed under the old read path, same order/types.
 EXEC(N'CREATE VIEW dbo.UsageSummary AS
 SELECT c.summary_id,c.user_id,c.product_id,c.period_type,c.period_start,
        p.period_end,c.total_tokens_used,c.total_upstream_consumed,
        c.request_count,c.last_updated_at
 FROM dbo.UsageSummaryCore c JOIN dbo.UsagePeriod p
   ON p.period_type=c.period_type AND p.period_start=c.period_start;');
 -- Object grants formerly on UsageSummary are retained by its renamed table ID.
 -- New table gets equivalent manager CRUD; old SELECT path restored for manager.
 GRANT SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.UsagePeriod TO hub_manager;
 GRANT SELECT ON OBJECT::dbo.UsageSummary TO hub_manager;
 -- Restore the pre-existing documented but absent tenth view on COPY ONLY.
 -- Definition is copied from sql/view.sql; this does NOT change source v0.1.
 IF @source_view_count=9
 BEGIN
  EXEC(N'CREATE VIEW dbo.v_CustomerService AS
  SELECT u.user_id,u.username,u.email,u.phone,u.status,u.created_at,
         (SELECT COUNT_BIG(*) FROM dbo.Orders o WHERE o.user_id=u.user_id) AS order_count,
         (SELECT COALESCE(SUM(o.total_amount),0) FROM dbo.Orders o
           WHERE o.user_id=u.user_id AND o.status=''paid'') AS paid_amount,
         (SELECT COALESCE(SUM(b.remaining_tokens),0) FROM dbo.TokenBalances b
           WHERE b.user_id=u.user_id) AS remaining_tokens
  FROM dbo.Users u;');
 END;
 GRANT SELECT ON OBJECT::dbo.v_CustomerService TO hub_manager,hub_staff;
 -- Align the other documented legacy view that is incomplete in v0.1_A.
 -- This is the official sql/view.sql shape, preserving the fixed snapshot time.
 EXEC(N'CREATE OR ALTER VIEW dbo.v_InventoryStatus AS
 SELECT a.account_id,a.provider,a.account_name,a.status,
        i.current_quota,a.safety_threshold,a.expires_at,
        CAST(''2026-09-22T23:59:59'' AS DATETIME2(0)) AS as_of_time,
        CASE WHEN a.status=''active''
          AND (a.expires_at IS NULL OR a.expires_at>''2026-09-22T23:59:59'')
          THEN ''usable'' ELSE ''unusable'' END AS account_state,
        CASE WHEN i.current_quota<a.safety_threshold THEN ''low'' ELSE ''normal'' END AS stock_state,
        i.current_quota-a.safety_threshold AS quota_headroom
 FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id;');
 GRANT SELECT ON OBJECT::dbo.v_InventoryStatus TO hub_manager,hub_staff;
 IF COL_LENGTH('dbo.v_InventoryStatus','quota_headroom') IS NULL
  THROW 51613, 'Inventory status view schema mismatch', 1;
 IF (SELECT COUNT_BIG(*) FROM dbo.UsageSummaryCore)<>3394
    OR (SELECT COUNT_BIG(*) FROM dbo.UsageSummary)<>3394
    OR (SELECT COUNT(*) FROM dbo.UsagePeriod)<>99
    THROW 51608, 'Post-migration row count/compatibility view mismatch', 1;
 IF EXISTS(SELECT 1 FROM sys.foreign_keys WHERE is_disabled=1 OR is_not_trusted=1)
    OR EXISTS(SELECT 1 FROM sys.check_constraints WHERE is_disabled=1 OR is_not_trusted=1)
    THROW 51609, 'Post-migration constraint disabled/untrusted', 1;
 IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>15
    OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled=0 AND is_not_trusted=0)<>18
    OR (SELECT COUNT(*) FROM sys.views WHERE is_ms_shipped=0)<>11
    THROW 51610, 'Post-migration table/FK/view counts do not match expected schema', 1;
 COMMIT TRANSACTION;
 PRINT 'PASS W6 MIGRATION: 3394 summaries, 99 normalized period keys, 15 tables, 18 FK, 11 views';
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
IF @@TRANCOUNT<>0 THROW 51611, 'Open transaction after migration', 1;
