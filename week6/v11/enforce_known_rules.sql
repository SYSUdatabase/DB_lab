-- Isolated v1.1: protect final orders, incoming usage and known typed log refs.
-- Historical v1.0 rows are NOT rewritten. Guards apply to future INSERT/UPDATE.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'TokenHubDB_v11_Issues_20261014'
 THROW 51910,'Wrong target; refuse to change v0.1/v1.0',1;
IF OBJECT_ID(N'dbo.UsagePeriod',N'U') IS NULL OR OBJECT_ID(N'dbo.UsageSummaryCore',N'U') IS NULL
 THROW 51911,'v1.0 baseline schema missing',1;
IF OBJECT_ID(N'dbo.trg_W5_OrdersFinalized',N'TR') IS NOT NULL
 THROW 51912,'Fixes already applied; do not reapply blindly',1;
GO
BEGIN TRANSACTION;
GO
CREATE TRIGGER dbo.trg_W5_OrdersFinalized ON dbo.Orders AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS (
  SELECT 1 FROM inserted o
  OUTER APPLY(
   SELECT COUNT_BIG(*) detail_count,SUM(d.subtotal) total_amount,
          SUM(d.total_tokens) total_tokens
   FROM dbo.OrderDetails d WHERE d.order_id=o.order_id
  ) agg
  WHERE o.status IN ('paid','refunded')
  AND (agg.detail_count<1 OR o.total_amount<>agg.total_amount
       OR o.total_tokens<>agg.total_tokens)
 )
 THROW 51920,'Finalized order requires at least one detail and matching totals',1;
END;
GO
CREATE TRIGGER dbo.trg_W5_NoEditFinalizedDetails ON dbo.OrderDetails AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS (
  SELECT 1 FROM (
   SELECT order_id FROM inserted UNION SELECT order_id FROM deleted
  ) x JOIN dbo.Orders o ON o.order_id=x.order_id
  WHERE o.status IN ('paid','refunded')
 )
 THROW 51921,'Finalized order detail is immutable; edit pending draft before payment',1;
END;
GO
CREATE TRIGGER dbo.trg_W5_UsageNewValidity ON dbo.TokenUsageLogs AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS (
  SELECT 1 FROM inserted i
  JOIN dbo.Users u ON u.user_id=i.user_id
  JOIN dbo.Products p ON p.product_id=i.product_id
  JOIN dbo.UpstreamAccount a ON a.account_id=i.account_id
  WHERE i.used_at<u.created_at OR i.used_at<a.created_at
    OR (a.expires_at IS NOT NULL AND i.used_at>=a.expires_at)
    OR p.model_provider<>a.provider
 )
 THROW 51922,'Usage timestamp, registration, provider or account validity failed',1;
END;
GO
CREATE TRIGGER dbo.trg_W5_InventoryLogRefs ON dbo.InventoryLog AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS (
  SELECT 1 FROM inserted i
  WHERE (i.reference_type IS NULL AND i.reference_id IS NOT NULL)
     OR (i.reference_type='order'
         AND (i.reference_id IS NULL OR NOT EXISTS(
           SELECT 1 FROM dbo.Orders o WHERE o.order_id=i.reference_id)))
     OR (i.reference_type='restock_task'
         AND (i.reference_id IS NULL OR NOT EXISTS(
           SELECT 1 FROM dbo.RestockTask t WHERE t.task_id=i.reference_id)))
 )
 THROW 51923,'New inventory log has an invalid typed reference',1;
 -- reference_type=manual is kept as opaque legacy reference; no invented FK.
END;
GO
CREATE TRIGGER dbo.trg_W5_ExceptionRefs ON dbo.ExceptionLog AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS (
  SELECT 1 FROM inserted e
  WHERE (e.related_table IS NULL AND e.related_id IS NOT NULL)
     OR (e.related_table IS NOT NULL AND e.related_id IS NULL)
     OR (e.related_table IS NOT NULL AND e.related_table NOT IN
        ('Orders','Inventory','TokenUsageLogs'))
     OR (e.related_table='Orders' AND NOT EXISTS(
          SELECT 1 FROM dbo.Orders o WHERE o.order_id=e.related_id))
     OR (e.related_table='Inventory' AND NOT EXISTS(
          SELECT 1 FROM dbo.Inventory i WHERE i.inventory_id=e.related_id))
     OR (e.related_table='TokenUsageLogs' AND NOT EXISTS(
          SELECT 1 FROM dbo.TokenUsageLogs u WHERE u.log_id=e.related_id))
 )
 THROW 51924,'New exception has an invalid typed reference',1;
END;
GO
IF OBJECT_ID(N'dbo.trg_W5_OrdersFinalized',N'TR') IS NULL
 OR OBJECT_ID(N'dbo.trg_W5_NoEditFinalizedDetails',N'TR') IS NULL
 OR OBJECT_ID(N'dbo.trg_W5_UsageNewValidity',N'TR') IS NULL
 OR OBJECT_ID(N'dbo.trg_W5_InventoryLogRefs',N'TR') IS NULL
 OR OBJECT_ID(N'dbo.trg_W5_ExceptionRefs',N'TR') IS NULL
 THROW 51925,'Trigger deployment incomplete',1;
COMMIT TRANSACTION;
PRINT N'PASS five insert/update protections installed on isolated v1.1';
GO