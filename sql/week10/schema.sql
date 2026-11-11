-- All batches participate in install.sql's single atomic migration transaction.
CREATE SCHEMA w10 AUTHORIZATION dbo;
GO
IF EXISTS(SELECT 1 FROM dbo.OrderDetails WHERE subtotal<>CONVERT(DECIMAL(19,2),quantity)*unit_price
 OR total_tokens<>CONVERT(BIGINT,quantity)*tokens_per_unit)
 THROW 56009,'Legacy detail snapshots are inconsistent',1;
IF EXISTS(SELECT 1 FROM sys.triggers WHERE object_id=OBJECT_ID('dbo.trg_W5_NoEditFinalizedDetails') AND is_disabled=1)
 THROW 56009,'Finalized detail guard must be enabled before migration',1;
ALTER TABLE dbo.Orders ADD pricing_rule_version VARCHAR(32) NOT NULL
 CONSTRAINT DF_W10_OrderRule DEFAULT('legacy') WITH VALUES;
ALTER TABLE dbo.OrderDetails ADD original_subtotal DECIMAL(10,2) NULL,
 discount_rate DECIMAL(5,4) NOT NULL CONSTRAINT DF_W10_DiscountRate DEFAULT(0) WITH VALUES,
 discount_amount DECIMAL(10,2) NOT NULL CONSTRAINT DF_W10_DiscountAmount DEFAULT(0) WITH VALUES,
 pricing_rule_version VARCHAR(32) NOT NULL CONSTRAINT DF_W10_DetailRule DEFAULT('legacy') WITH VALUES;
GO
-- DDL and the temporary guard disable roll back together if any later batch fails.
DISABLE TRIGGER dbo.trg_W5_NoEditFinalizedDetails ON dbo.OrderDetails;
UPDATE dbo.OrderDetails SET original_subtotal=subtotal;
ENABLE TRIGGER dbo.trg_W5_NoEditFinalizedDetails ON dbo.OrderDetails;
ALTER TABLE dbo.OrderDetails ALTER COLUMN original_subtotal DECIMAL(10,2) NOT NULL;
ALTER TABLE dbo.OrderDetails DROP CONSTRAINT CK_OrderDetails_subtotal_formula;
ALTER TABLE dbo.OrderDetails WITH CHECK ADD CONSTRAINT CK_OrderDetails_subtotal_formula CHECK (
 original_subtotal=CONVERT(DECIMAL(19,2),quantity)*unit_price
 AND subtotal=original_subtotal-discount_amount
 AND discount_amount=CONVERT(DECIMAL(10,2),ROUND(original_subtotal*discount_rate,2))
 AND ((pricing_rule_version='legacy' AND discount_rate=0)
 OR (pricing_rule_version='amount-v1' AND discount_rate IN(0,0.05,0.10))));
ALTER TABLE dbo.Orders WITH CHECK ADD CONSTRAINT CK_W10_OrderRule CHECK(pricing_rule_version IN('legacy','amount-v1'));
CREATE TABLE w10.InventoryAdjustments (
 adjustment_id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_W10_Adjustments PRIMARY KEY,
 operation_key UNIQUEIDENTIFIER NOT NULL CONSTRAINT UQ_W10_AdjustmentKey UNIQUE,
 product_id INT NOT NULL REFERENCES dbo.Products(product_id),
 account_id INT NOT NULL REFERENCES dbo.UpstreamAccount(account_id),
 operator_id INT NOT NULL REFERENCES dbo.Employees(employee_id),
 change_amount BIGINT NOT NULL,
 reason NVARCHAR(255) NOT NULL,
 before_current_quota BIGINT NOT NULL,
 after_current_quota BIGINT NOT NULL,
 before_total_quota BIGINT NOT NULL,
 after_total_quota BIGINT NOT NULL,
 log_id INT NOT NULL CONSTRAINT UQ_W10_AdjustmentLog UNIQUE REFERENCES dbo.InventoryLog(log_id),
 created_at DATETIME2(0) NOT NULL,
 CONSTRAINT CK_W10_Adjustment CHECK(change_amount<>0 AND LEN(TRIM(reason))>0
 AND before_current_quota>=0 AND after_current_quota>=0
 AND before_total_quota>0 AND after_total_quota>0
 AND CONVERT(DECIMAL(20,0),after_current_quota)-before_current_quota=change_amount
 AND CONVERT(DECIMAL(20,0),after_total_quota)-before_total_quota=change_amount)
);
GO
CREATE TRIGGER w10.trg_AdjustmentsImmutable ON w10.InventoryAdjustments AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 THROW 56009,'Inventory adjustment records are immutable',1;
END;
GO
CREATE OR ALTER TRIGGER dbo.trg_W5_NoEditFinalizedDetails ON dbo.OrderDetails AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF EXISTS(SELECT 1 FROM (SELECT order_id FROM inserted UNION SELECT order_id FROM deleted) x
  JOIN dbo.Orders o ON o.order_id=x.order_id WHERE o.status IN('paid','refunded','partially_refunded'))
  THROW 51921,'Finalized order detail is immutable; edit pending draft before payment',1;
END;
GO
