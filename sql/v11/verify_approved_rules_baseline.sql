-- Read-only final verification of approved I02/I03/I04/I07 v1.1 schema.
:on error exit
SET NOCOUNT ON;
IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
 THROW 52180,'Wrong database',1;
IF NOT EXISTS(SELECT 1 FROM sys.key_constraints
 WHERE name='UQ_OrderDetails_order_product' AND type='UQ')
 THROW 52181,'I02 UNIQUE missing',1;
IF OBJECT_ID('dbo.usp_W5_AddMergedOrderItem','P') IS NULL
 OR OBJECT_ID('dbo.usp_W5_CreateRegisteredOrder','P') IS NULL
 THROW 52182,'I02/I03 procedures missing',1;
IF NOT EXISTS(SELECT 1 FROM sys.columns
 WHERE object_id=OBJECT_ID('dbo.Orders') AND name='user_id' AND is_nullable=0)
 OR NOT EXISTS(SELECT 1 FROM sys.foreign_keys
 WHERE name='FK_Orders_Users' AND is_disabled=0 AND is_not_trusted=0)
 THROW 52183,'I03 registered order FK missing',1;
IF EXISTS(SELECT 1 FROM dbo.Orders o LEFT JOIN dbo.Users u ON o.user_id=u.user_id
 WHERE u.user_id IS NULL)
 THROW 52184,'I03 orphan historical order',1;
IF NOT EXISTS(SELECT 1 FROM sys.key_constraints
 WHERE name='UQ_Inventory_account' AND type='UQ')
 OR OBJECT_ID('dbo.trg_W5_AutoInventoryOnAccount','TR') IS NULL
 OR OBJECT_ID('dbo.trg_W5_PreventInventoryDetach','TR') IS NULL
 THROW 52185,'I04 inventory uniqueness/triggers missing',1;
IF EXISTS(SELECT 1 FROM dbo.UpstreamAccount a
 WHERE NOT EXISTS(SELECT 1 FROM dbo.Inventory i WHERE i.account_id=a.account_id))
 THROW 52186,'I04 account without inventory',1;
IF EXISTS(SELECT 1 FROM dbo.Inventory i JOIN dbo.UpstreamAccount a
 ON a.account_id=i.account_id
 WHERE i.current_quota<>a.total_quota-a.used_quota)
 THROW 52187,'I04 existing inventory mismatched',1;
IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.RestockTask')
 AND name='created_by' AND is_nullable=1)
 OR NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.RestockTask')
 AND name='created_source' AND is_nullable=0)
 OR NOT EXISTS(SELECT 1 FROM sys.check_constraints
 WHERE name='CK_RestockTask_creator_source' AND is_disabled=0 AND is_not_trusted=0)
 OR NOT EXISTS(SELECT 1 FROM sys.foreign_keys
 WHERE name='FK_RestockTask_CreatedBy' AND is_disabled=0 AND is_not_trusted=0)
 THROW 52188,'I07 creator source constraints missing',1;
IF EXISTS(SELECT 1 FROM dbo.RestockTask
 WHERE (created_source='manual' AND created_by IS NULL)
    OR (created_source='system' AND created_by IS NOT NULL)
    OR created_source NOT IN ('manual','system'))
 THROW 52189,'I07 old task rows invalid',1;
IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>15
 OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled=0 AND is_not_trusted=0)<>18
 OR (SELECT COUNT(*) FROM sys.triggers WHERE name LIKE 'trg_W5_%' AND is_disabled=0)<>13
 THROW 52190,'Other schema count changed unexpectedly',1;
SELECT (SELECT COUNT(*) FROM dbo.UpstreamAccount) AS accounts,
       (SELECT COUNT(*) FROM dbo.Inventory) AS inventories,
       (SELECT COUNT(*) FROM dbo.RestockTask) AS existing_tasks,
       (SELECT COUNT(*) FROM dbo.RestockTask WHERE created_source='manual') AS manual_tasks;
PRINT 'PASS I02 I03 I04 I07 metadata, source data and trusted constraints';
