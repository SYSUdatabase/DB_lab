SET NOCOUNT ON;
IF DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]Web%'
 THROW 55000,'Only Web application databases are supported',1;
IF OBJECT_ID('dbo.trg_App_OpeningInventory','TR') IS NULL
 THROW 55009,'Opening inventory trigger missing',1;
IF EXISTS(
 SELECT 1 FROM dbo.UpstreamAccount a
 FULL OUTER JOIN dbo.Inventory i ON i.account_id=a.account_id
 LEFT JOIN (SELECT account_id,SUM(CONVERT(bigint,change_amount)) amount
  FROM dbo.InventoryLog GROUP BY account_id) l ON l.account_id=a.account_id
 WHERE a.account_id IS NULL OR i.account_id IS NULL OR i.current_quota<0
  OR i.current_quota<>a.total_quota-a.used_quota OR i.current_quota<>COALESCE(l.amount,0)
)
 THROW 55009,'Account/inventory/movement reconciliation failed',1;
SELECT account_id,change_amount,created_at FROM dbo.InventoryLog
 WHERE reason=N'APP_INITIAL_QUOTA_V1' ORDER BY account_id;
PRINT 'PASS account, inventory and movement reconciliation';
