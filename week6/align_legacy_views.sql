-- P3b: repair pre-existing view drift on the isolated v1.0 copy.
-- This definition matches official sql/view.sql and preserves quota semantics.
-- Original TokenHubDB_v01_A is never modified.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME()<>N'TokenHubDB_v10_W6_20261014'
 THROW 51820,'Refuse to alter a database other than isolated v1.0 target',1;
IF OBJECT_ID('dbo.UsagePeriod','U') IS NULL
 OR OBJECT_ID('dbo.v_InventoryStatus','V') IS NULL
 THROW 51821,'Expected normalized target or legacy view is missing',1;
BEGIN TRY
 BEGIN TRAN;
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
  OR COL_LENGTH('dbo.v_InventoryStatus','account_state') IS NULL
  THROW 51822,'View columns are incomplete',1;
 COMMIT TRAN;
 PRINT 'PASS W6 align v_InventoryStatus with formal v0.1 view definition';
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRAN;
 THROW;
END CATCH;
