-- I02/I03/I04/I07 approved rules. Isolated v1.1 copy only.
-- Preserve previous v1.0 schema/data and prior v1.1 guard scripts.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME()<>N'TokenHubDB_v11_Issues_20261014'
 THROW 52100,'Refuse to modify any other database',1;
IF OBJECT_ID('dbo.UsagePeriod','U') IS NULL
 OR OBJECT_ID('dbo.trg_W5_OrdersFinalized','TR') IS NULL
 OR OBJECT_ID('dbo.trg_W5_UsageManagedOnly','TR') IS NULL
 THROW 52101,'Expected original v1.1 installation missing',1;
IF COL_LENGTH('dbo.RestockTask','created_source') IS NOT NULL
 OR OBJECT_ID('dbo.trg_W5_AutoInventoryOnAccount','TR') IS NOT NULL
 THROW 52102,'Approved patch already installed',1;
IF EXISTS(
 SELECT 1 FROM dbo.UpstreamAccount a WHERE NOT EXISTS(
   SELECT 1 FROM dbo.Inventory i WHERE i.account_id=a.account_id))
 THROW 52103,'Existing account lacks Inventory; stop, do not invent quotas',1;
IF EXISTS(
 SELECT 1 FROM dbo.Inventory i JOIN dbo.UpstreamAccount a ON a.account_id=i.account_id
 WHERE i.current_quota<>a.total_quota-a.used_quota)
 THROW 52104,'Existing inventory does not match account balance',1;
IF (SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled=0 AND is_not_trusted=0)<>18
 THROW 52105,'Unexpected existing FK set',1;
IF NOT EXISTS(SELECT 1 FROM sys.key_constraints
 WHERE name='UQ_OrderDetails_order_product' AND type='UQ')
 THROW 52106,'I02 UNIQUE missing',1;
GO
BEGIN TRANSACTION;
GO
-- I07: retain existing manual employee references, add system source.
ALTER TABLE dbo.RestockTask DROP CONSTRAINT FK_RestockTask_CreatedBy;
ALTER TABLE dbo.RestockTask ALTER COLUMN created_by INT NULL;
ALTER TABLE dbo.RestockTask ADD
 created_source VARCHAR(10) NOT NULL
  CONSTRAINT DF_RestockTask_created_source DEFAULT('manual') WITH VALUES;
GO
ALTER TABLE dbo.RestockTask WITH CHECK ADD
 CONSTRAINT CK_RestockTask_creator_source CHECK(
  (created_source='manual' AND created_by IS NOT NULL)
  OR (created_source='system' AND created_by IS NULL));
ALTER TABLE dbo.RestockTask WITH CHECK ADD
 CONSTRAINT FK_RestockTask_CreatedBy FOREIGN KEY(created_by)
 REFERENCES dbo.Employees(employee_id);
GO
-- I04: parent create always produces exactly one child in the same statement.
CREATE TRIGGER dbo.trg_W5_AutoInventoryOnAccount
ON dbo.UpstreamAccount AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 INSERT dbo.Inventory(account_id,current_quota,last_updated_at)
 SELECT i.account_id,i.total_quota-i.used_quota,i.updated_at
 FROM inserted i
 WHERE NOT EXISTS (
  SELECT 1 FROM dbo.Inventory v WITH(UPDLOCK,HOLDLOCK)
  WHERE v.account_id=i.account_id
 );
 IF EXISTS(
  SELECT 1 FROM inserted i LEFT JOIN dbo.Inventory v ON v.account_id=i.account_id
  WHERE v.account_id IS NULL OR v.current_quota<>i.total_quota-i.used_quota
 ) THROW 52107,'Account insertion must create matching Inventory',1;
END;
GO
-- I04: cannot delete or reassign a child and leave an existing parent uncovered.
CREATE TRIGGER dbo.trg_W5_PreventInventoryDetach
ON dbo.Inventory AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(
 SELECT 1 FROM deleted d JOIN dbo.UpstreamAccount a ON a.account_id=d.account_id
 WHERE NOT EXISTS(SELECT 1 FROM dbo.Inventory v WHERE v.account_id=a.account_id)
 )
 THROW 52108,'Inventory row is required for every UpstreamAccount',1;
END;
GO
-- I03: all new orders use an existing active, already-registered user.
-- Orders.user_id NOT NULL + FK_Orders_Users additionally block nonexistent users.
CREATE TRIGGER dbo.trg_W5_NewOrdersRegistered
ON dbo.Orders AFTER INSERT AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(
 SELECT 1 FROM inserted i JOIN dbo.Users u ON u.user_id=i.user_id
 WHERE u.status<>'active' OR i.created_at<u.created_at
 ) THROW 52109,'Register an active user before creating an order',1;
END;
GO
IF COL_LENGTH('dbo.RestockTask','created_source') IS NULL
 OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled=0 AND is_not_trusted=0)<>18
 OR (SELECT COUNT(*) FROM sys.triggers WHERE name LIKE 'trg_W5_%')<>13
 OR EXISTS(SELECT 1 FROM sys.check_constraints WHERE is_disabled=1 OR is_not_trusted=1)
 THROW 52110,'Approved patch schema/constraint verification failed',1;
IF EXISTS(SELECT 1 FROM dbo.RestockTask WHERE created_by IS NULL)
 THROW 52111,'Existing manual task owners were not preserved',1;
-- The trusted CHECK and DEFAULT metadata validate created_source in this deployment.
IF NOT EXISTS(SELECT 1 FROM sys.check_constraints
 WHERE name='CK_RestockTask_creator_source' AND is_disabled=0 AND is_not_trusted=0)
 THROW 52112,'Creator source CHECK is not trusted',1;
COMMIT TRANSACTION;
PRINT 'PASS approved I02/I03/I04/I07 schema and 3 triggers deployed';
GO