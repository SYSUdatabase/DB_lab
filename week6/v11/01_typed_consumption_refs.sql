-- v1.1 extension: convert ONLY provably matched generated consumption references.
-- Apply after deterministic historical repair. No change to business amounts/quotas.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME()<>N'TokenHubDB_v11_Issues_20261014'
 THROW 53000,'Only the approved isolated v1.1 target is permitted',1;
IF OBJECT_ID('dbo.trg_W5_InventoryLogRefs','TR') IS NULL
 OR OBJECT_ID('dbo.usp_W5_RecordUsage','P') IS NULL
 OR OBJECT_ID('dbo.trg_W6_InventoryTypedRefs','TR') IS NOT NULL
 THROW 53001,'Required v1.1 objects missing or patch already applied',1;
IF (SELECT COUNT(*) FROM dbo.InventoryLog
 WHERE reference_type='manual' AND reference_id IS NOT NULL)<>3000
 THROW 53002,'Expected synthetic usage-link count does not match',1;
IF EXISTS(
 SELECT 1 FROM dbo.InventoryLog l
 WHERE l.reference_type='manual' AND l.reference_id IS NOT NULL
   AND NOT EXISTS (
    SELECT 1 FROM dbo.TokenUsageLogs u WHERE u.log_id=l.reference_id
      AND u.account_id=l.account_id
      AND l.change_amount=-CONVERT(BIGINT,u.upstream_tokens_consumed)
      AND l.created_at=u.used_at AND l.change_type='consumption')
) THROW 53003,'Opaque manual reference cannot be proven as one usage event',1;
IF EXISTS(SELECT 1 FROM dbo.TokenUsageLogs u WHERE NOT EXISTS(
 SELECT 1 FROM dbo.InventoryLog l WHERE l.reference_type='manual'
   AND l.reference_id=u.log_id AND l.account_id=u.account_id
   AND l.created_at=u.used_at
   AND l.change_amount=-CONVERT(BIGINT,u.upstream_tokens_consumed)))
 THROW 53004,'Not every usage event has its matching single audit entry',1;
GO
BEGIN TRANSACTION;
ALTER TABLE dbo.InventoryLog DROP CONSTRAINT CK_InventoryLog_reference_type;
ALTER TABLE dbo.InventoryLog WITH CHECK ADD CONSTRAINT CK_InventoryLog_reference_type
 CHECK (reference_type IS NULL OR reference_type IN ('order','restock_task','manual','usage'));
UPDATE dbo.InventoryLog SET reference_type='usage'
WHERE reference_type='manual' AND reference_id IS NOT NULL;
IF @@ROWCOUNT<>3000 THROW 53005,'Usage-link conversion row count mismatch',1;
IF EXISTS(SELECT 1 FROM sys.check_constraints
 WHERE name='CK_InventoryLog_reference_type' AND (is_disabled=1 OR is_not_trusted=1))
 THROW 53006,'New reference-type CHECK is not trusted',1;
COMMIT TRANSACTION;
GO
CREATE TRIGGER dbo.trg_W6_InventoryTypedRefs ON dbo.InventoryLog
AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM inserted l WHERE
    (l.reference_type='manual' AND l.reference_id IS NOT NULL)
    OR (l.reference_type IS NULL AND l.reference_id IS NOT NULL)
    OR (l.reference_type='usage' AND (l.reference_id IS NULL OR NOT EXISTS(
      SELECT 1 FROM dbo.TokenUsageLogs u WHERE u.log_id=l.reference_id
        AND u.account_id=l.account_id
        AND l.created_at=u.used_at AND l.change_type='consumption'
        AND l.change_amount=-CONVERT(BIGINT,u.upstream_tokens_consumed))))
 )
 THROW 53007,'New inventory audit reference is inconsistent',1;
END;
GO
CREATE TRIGGER dbo.trg_W6_ProtectConsumptionReferences
ON dbo.TokenUsageLogs AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 -- Generated usage events are immutable after reconciliation. Future events
 -- are appended through the owner-executed usage procedure only.
 THROW 53008,'Audit usage events are append-only; no UPDATE/DELETE',1;
END;
GO
IF (SELECT COUNT(*) FROM dbo.InventoryLog WHERE reference_type='usage')<>3000
 OR EXISTS(SELECT 1 FROM dbo.InventoryLog l LEFT JOIN dbo.TokenUsageLogs u
          ON u.log_id=l.reference_id WHERE l.reference_type='usage'
          AND (u.log_id IS NULL OR u.account_id<>l.account_id OR l.created_at<>u.used_at
               OR l.change_amount<>-CONVERT(BIGINT,u.upstream_tokens_consumed)))
 THROW 53009,'Typed usage audit reconciliation failed',1;
PRINT 'PASS I08 3000 synthetic usage ledger references validated and typed';
GO
