-- Shared by fresh installation and the guarded existing-database repair.
GO
CREATE OR ALTER TRIGGER dbo.trg_App_OpeningInventory
ON dbo.UpstreamAccount WITH EXECUTE AS OWNER AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.InventoryLog(account_id,change_type,change_amount,reference_type,reference_id,reason,created_at)
 SELECT account_id,'purchase',total_quota-used_quota,'manual',NULL,N'APP_INITIAL_QUOTA_V1',created_at
 FROM inserted WHERE total_quota-used_quota>0;
END;
GO
CREATE OR ALTER TRIGGER dbo.trg_W6_InventoryLogWrite ON dbo.InventoryLog
AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted)
 BEGIN
  -- Only the owner-controlled unused-account deletion may remove its opening row.
  IF USER_NAME()='dbo' AND TRY_CONVERT(INT,SESSION_CONTEXT(N'app_account_delete'))=1
   AND @@TRANCOUNT>0 AND NOT EXISTS(SELECT 1 FROM inserted)
   AND NOT EXISTS(SELECT 1 FROM deleted WHERE reason<>N'APP_INITIAL_QUOTA_V1' OR reason IS NULL
    OR change_type<>'purchase' OR reference_type<>'manual' OR reference_type IS NULL
    OR reference_id IS NOT NULL OR change_amount<=0)
   AND NOT EXISTS(SELECT 1 FROM deleted d JOIN dbo.TokenUsageLogs u ON u.account_id=d.account_id)
   AND NOT EXISTS(SELECT 1 FROM deleted d JOIN dbo.RestockTask t ON t.account_id=d.account_id)
   AND NOT EXISTS(SELECT 1 FROM deleted d JOIN dbo.InventoryLog l ON l.account_id=d.account_id)
   RETURN;
  THROW 53120,'Inventory movement logs are append-only',1;
 END;
 IF USER_NAME()<>'dbo'
  THROW 53121,'Inventory movement must be appended through an owner-controlled procedure',1;
END;
GO
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.InventoryLog') AND name='UX_App_OpeningInventory')
 CREATE UNIQUE INDEX UX_App_OpeningInventory ON dbo.InventoryLog(account_id)
 WHERE reason=N'APP_INITIAL_QUOTA_V1';
GO
