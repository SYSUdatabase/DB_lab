-- v1.1 refund extension: lot provenance and a cash refund obligation ledger.
-- ONLY deploy after historical seed reconciliation on a BACKED-UP isolated v1.1.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'TokenHubDB_v11_Issues_20261014'
 THROW 54001,'Refuse non-isolated v1.1 refund schema target',1;
IF OBJECT_ID('dbo.usp_W6_PayPendingOrder','P') IS NULL
 OR OBJECT_ID('dbo.usp_W5_RecordUsage','P') IS NULL
 OR OBJECT_ID('dbo.trg_W6_OrdersHistory','TR') IS NULL
 THROW 54002,'Previous v1.1 hardening is missing',1;
IF OBJECT_ID('dbo.OrderTokenLots','U') IS NOT NULL
 OR OBJECT_ID('dbo.RefundLedger','U') IS NOT NULL
 THROW 54003,'Refund schema exists; do not install twice',1;
GO
BEGIN TRANSACTION;
CREATE TABLE dbo.OrderTokenLots(
 detail_id INT NOT NULL CONSTRAINT PK_OrderTokenLots PRIMARY KEY,
 credited_at DATETIME2(0) NOT NULL,
 issued_tokens BIGINT NOT NULL,
 consumed_tokens BIGINT NOT NULL CONSTRAINT DF_Lot_consumed DEFAULT(0),
 refunded_tokens BIGINT NOT NULL CONSTRAINT DF_Lot_refunded DEFAULT(0),
 CONSTRAINT FK_Lots_OrderDetails FOREIGN KEY(detail_id) REFERENCES dbo.OrderDetails(detail_id),
 CONSTRAINT CK_Lot_Quantity CHECK(
 issued_tokens>0 AND consumed_tokens>=0 AND refunded_tokens>=0
 AND consumed_tokens<=issued_tokens
 AND refunded_tokens<=issued_tokens-consumed_tokens)
);
CREATE TABLE dbo.RefundLedger(
 refund_id INT IDENTITY(1,1) NOT NULL CONSTRAINT UQ_RefundLedger_id UNIQUE,
 order_id INT NOT NULL CONSTRAINT PK_RefundLedger PRIMARY KEY,
 requested_at DATETIME2(0) NOT NULL,
 refund_amount DECIMAL(10,2) NOT NULL,
 refundable_tokens BIGINT NOT NULL,
 consumed_tokens BIGINT NOT NULL,
 payout_state VARCHAR(24) NOT NULL CONSTRAINT DF_Refund_state DEFAULT('awaiting_transfer'),
 external_payout_ref VARCHAR(120) NULL CONSTRAINT UQ_Refund_external_ref UNIQUE,
 settled_at DATETIME2(0) NULL,
 CONSTRAINT FK_RefundLedger_Order FOREIGN KEY(order_id) REFERENCES dbo.Orders(order_id),
 CONSTRAINT CK_Refund_positive CHECK (refund_amount>0 AND refundable_tokens>0 AND consumed_tokens>=0),
 CONSTRAINT CK_Refund_state CHECK(
  (payout_state='awaiting_transfer' AND settled_at IS NULL AND external_payout_ref IS NULL)
  OR (payout_state='settled' AND settled_at IS NOT NULL AND external_payout_ref IS NOT NULL
      AND LEN(external_payout_ref)>=6))
);
ALTER TABLE dbo.Orders DROP CONSTRAINT CK_Orders_status;
ALTER TABLE dbo.Orders WITH CHECK ADD CONSTRAINT CK_Orders_status
 CHECK (status IN ('pending','paid','cancelled','refunded','partially_refunded'));
ALTER TABLE dbo.Orders DROP CONSTRAINT CK_Orders_payment_time;
ALTER TABLE dbo.Orders WITH CHECK ADD CONSTRAINT CK_Orders_payment_time
 CHECK ((status IN ('paid','refunded','partially_refunded')
            AND paid_at IS NOT NULL AND paid_at>=created_at)
     OR (status IN ('pending','cancelled') AND paid_at IS NULL));
COMMIT TRANSACTION;
GO
CREATE TRIGGER dbo.trg_W11_TokenLotGuard ON dbo.OrderTokenLots
AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF USER_NAME()<>'dbo'
  THROW 54010,'Token lots may only change inside owner-executed accounting',1;
 IF EXISTS(SELECT 1 FROM inserted l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id
   JOIN dbo.Orders o ON o.order_id=d.order_id
   WHERE o.status NOT IN ('paid','refunded','partially_refunded')
     OR l.issued_tokens<>d.total_tokens OR l.credited_at<>o.paid_at)
  THROW 54011,'Lot amount/date inconsistent with paid detail',1;
END;
GO
CREATE TRIGGER dbo.trg_W11_RefundLedgerGuard ON dbo.RefundLedger
AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF USER_NAME()<>'dbo'
  THROW 54012,'Refund ledger only changed via owner-executed process',1;
 IF EXISTS(SELECT 1 FROM deleted d WHERE NOT EXISTS(
       SELECT 1 FROM inserted i WHERE i.order_id=d.order_id))
  THROW 54013,'Refund accounting rows cannot be deleted',1;
 IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.order_id=i.order_id
     WHERE i.refund_amount<>d.refund_amount
       OR i.refundable_tokens<>d.refundable_tokens
       OR i.consumed_tokens<>d.consumed_tokens
       OR i.requested_at<>d.requested_at)
  THROW 54014,'Recorded refund financial amounts are immutable',1;
END;
GO
IF (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0)<>17
 OR (SELECT COUNT(*) FROM sys.foreign_keys WHERE is_disabled=0 AND is_not_trusted=0)<>20
 THROW 54015,'Refund schema expected 17 physical tables and 20 trusted FKs',1;
PRINT 'PASS isolated refund schema and refund liability tracking installed';
GO
