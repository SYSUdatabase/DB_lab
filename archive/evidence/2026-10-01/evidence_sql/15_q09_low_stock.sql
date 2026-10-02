SET NOCOUNT ON;
SET XACT_ABORT ON;
PRINT N'Q09 - low stock purchase plus quota deduction, boundary case rolled back';
PRINT N'-- accounts already below the safety threshold';
SELECT a.account_id,a.provider,a.account_name,i.current_quota,a.safety_threshold,
       v.account_state,v.stock_state,v.quota_headroom
FROM dbo.UpstreamAccount a
JOIN dbo.Inventory i ON i.account_id=a.account_id
JOIN dbo.v_InventoryStatus v ON v.account_id=a.account_id
WHERE i.current_quota<a.safety_threshold
ORDER BY a.account_id;

PRINT N'-- positive branch: new account purchased 1000, consumed 900, threshold 200';
BEGIN TRY
  BEGIN TRANSACTION;
  INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,
      used_quota,safety_threshold,status,expires_at)
  VALUES('Other',N'Q09低库存边界',N'DEMO_NOT_A_REAL_API_KEY_Q09',1000,900,200,
      'active','2027-12-31');
  DECLARE @probe_account INT=SCOPE_IDENTITY();
  INSERT dbo.Inventory(account_id,current_quota) VALUES(@probe_account,100);
  INSERT dbo.InventoryLog(account_id,change_type,change_amount,reason)
  VALUES(@probe_account,'purchase',1000,N'Q09期初采购'),
        (@probe_account,'consumption',-900,N'Q09消耗至阈值以下');
  SELECT a.account_id,a.provider,i.current_quota,a.safety_threshold,
         v.account_state,v.stock_state,v.quota_headroom
  FROM dbo.UpstreamAccount a
  JOIN dbo.Inventory i ON i.account_id=a.account_id
  JOIN dbo.v_InventoryStatus v ON v.account_id=a.account_id
  WHERE i.current_quota<a.safety_threshold ORDER BY a.account_id;
  SELECT COUNT(*) AS baseline_unchanged FROM dbo.UpstreamAccount;
  ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  THROW;
END CATCH
IF @@TRANCOUNT<>0 THROW 51401,N'Open transaction after Q09',1;
PRINT N'Q09 boundary rows rolled back; baseline data unchanged';