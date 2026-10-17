-- Extra v1.1 guards for parent deletes and managed event write path.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
 THROW 51980,'Refuse wrong database',1;
IF OBJECT_ID('dbo.trg_W5_UsageManagedOnly','TR') IS NOT NULL
 THROW 51981,'Extension already deployed',1;
GO
BEGIN TRANSACTION;
GO
CREATE TRIGGER dbo.trg_W5_UsageManagedOnly ON dbo.TokenUsageLogs
AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 -- Under usp_W5_RecordUsage WITH EXECUTE AS OWNER, USER_NAME() is dbo.
 -- Normal hub_manager direct manipulation of the event ledger is forbidden.
 IF USER_NAME()<>'dbo'
  THROW 51982,'Use dbo.usp_W5_RecordUsage; direct usage-log mutation is forbidden',1;
END;
GO
CREATE TRIGGER dbo.trg_W5_BlockDeleteReferencedOrders ON dbo.Orders AFTER DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted x JOIN dbo.InventoryLog l
  ON l.reference_type='order' AND l.reference_id=x.order_id)
 OR EXISTS(SELECT 1 FROM deleted x JOIN dbo.ExceptionLog e
  ON e.related_table='Orders' AND e.related_id=x.order_id)
  THROW 51983,'Cannot delete an order referenced by an audit event',1;
END;
GO
CREATE TRIGGER dbo.trg_W5_BlockDeleteReferencedInventory ON dbo.Inventory AFTER DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted x JOIN dbo.ExceptionLog e
  ON e.related_table='Inventory' AND e.related_id=x.inventory_id)
  THROW 51984,'Cannot delete inventory referenced by an exception',1;
END;
GO
CREATE TRIGGER dbo.trg_W5_BlockDeleteReferencedRestock ON dbo.RestockTask AFTER DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted x JOIN dbo.InventoryLog l
  ON l.reference_type='restock_task' AND l.reference_id=x.task_id)
  THROW 51985,'Cannot delete a restock task referenced by inventory events',1;
END;
GO
CREATE TRIGGER dbo.trg_W5_BlockDeleteReferencedUsage ON dbo.TokenUsageLogs AFTER DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM deleted x JOIN dbo.ExceptionLog e
  ON e.related_table='TokenUsageLogs' AND e.related_id=x.log_id)
  THROW 51986,'Cannot delete token usage referenced by exceptions',1;
END;
GO
IF (SELECT COUNT(*) FROM sys.triggers WHERE name LIKE 'trg_W5_%')<>10
 THROW 51987,'Expected ten v1.1 guards',1;
COMMIT TRANSACTION;
PRINT 'PASS audit-delete and managed usage protections installed';
GO