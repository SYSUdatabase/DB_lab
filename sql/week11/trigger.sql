-- 第11周触发器：库存审计与订单完成规则。由 sql/week11/install.sql 在同一事务内安装。
-- 本项目的库存对象是上游账号库存 dbo.Inventory（每个账号一行，按供应商对应商品）。
CREATE SCHEMA w11 AUTHORIZATION dbo;
GO
CREATE TABLE w11.InventoryAudit (
 audit_id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_W11_InventoryAudit PRIMARY KEY,
 inventory_id INT NOT NULL,
 account_id INT NOT NULL,
 provider VARCHAR(50) NULL,
 operation_type VARCHAR(10) NOT NULL,
 quota_before BIGINT NULL,
 quota_after BIGINT NULL,
 change_quantity BIGINT NOT NULL,
 operated_at DATETIME2(3) NOT NULL,
 operator NVARCHAR(128) NOT NULL,
 login_name NVARCHAR(128) NOT NULL,
 CONSTRAINT CK_W11_AuditType CHECK (operation_type IN ('insert','increase','decrease','delete')),
 CONSTRAINT CK_W11_AuditValues CHECK (
  (operation_type='insert' AND quota_before IS NULL AND quota_after IS NOT NULL)
  OR (operation_type='delete' AND quota_before IS NOT NULL AND quota_after IS NULL)
  OR (operation_type IN ('increase','decrease') AND quota_before IS NOT NULL AND quota_after IS NOT NULL)),
 CONSTRAINT CK_W11_AuditChange CHECK (
  CONVERT(DECIMAL(20,0),change_quantity)=CONVERT(DECIMAL(20,0),COALESCE(quota_after,0))-COALESCE(quota_before,0))
);
GO
CREATE INDEX IX_W11_InventoryAudit_Account ON w11.InventoryAudit(account_id,audit_id);
GO
CREATE TRIGGER w11.trg_InventoryAuditImmutable ON w11.InventoryAudit AFTER UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 THROW 54409,'Inventory audit records are append-only',1;
END;
GO
-- 库存审计：一次语句改多行时，inserted/deleted 按 inventory_id 全外连接逐行记录。
-- 只改 last_updated_at、数量不变的行不记录。操作人员取应用入口写入的会话上下文
-- tokenhub.actor（如 employee:7、user:44）；直接用 SQL 连接操作时记录登录名。会话上下文可由连接自行设置，
-- 因此另记 login_name=ORIGINAL_LOGIN()，即实际连接数据库的登录名，不能由会话上下文改写。
CREATE TRIGGER dbo.trg_W11_InventoryAudit ON dbo.Inventory AFTER INSERT,UPDATE,DELETE AS
BEGIN
 SET NOCOUNT ON;
 IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
 DECLARE @operator NVARCHAR(128)=COALESCE(CONVERT(NVARCHAR(128),SESSION_CONTEXT(N'tokenhub.actor')),
  N'sql:'+ORIGINAL_LOGIN());
 DECLARE @now DATETIME2(3)=SYSDATETIME();
 INSERT w11.InventoryAudit(inventory_id,account_id,provider,operation_type,
  quota_before,quota_after,change_quantity,operated_at,operator,login_name)
 SELECT COALESCE(i.inventory_id,d.inventory_id),COALESCE(i.account_id,d.account_id),a.provider,
  CASE WHEN d.inventory_id IS NULL THEN 'insert' WHEN i.inventory_id IS NULL THEN 'delete'
   WHEN i.current_quota>d.current_quota THEN 'increase' ELSE 'decrease' END,
  d.current_quota,i.current_quota,
  COALESCE(i.current_quota,0)-COALESCE(d.current_quota,0),@now,@operator,ORIGINAL_LOGIN()
 FROM inserted i FULL OUTER JOIN deleted d ON d.inventory_id=i.inventory_id
 LEFT JOIN dbo.UpstreamAccount a ON a.account_id=COALESCE(i.account_id,d.account_id)
 WHERE d.inventory_id IS NULL OR i.inventory_id IS NULL OR i.current_quota<>d.current_quota;
END;
GO
-- 可售余量（以上游库存为单位）：有效且未过期账号的当前库存之和，减去已售出但顾客尚未消费、
-- 也未退款部分将要消耗的上游库存。每份套餐消耗 required_upstream_tokens，批次剩余份数按
-- 剩余 Token ÷ 下单时每份 Token（tokens_per_unit）折算，向上取整。
-- 订单完成时不扣上游库存（扣减仍在模拟调用时发生），因此完成前用可售余量防止超卖。
CREATE FUNCTION w11.fn_ProviderSellable(@provider VARCHAR(50))
RETURNS TABLE AS RETURN
SELECT (SELECT COALESCE(SUM(CONVERT(DECIMAL(38,0),i.current_quota)),0)
  FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id
  WHERE a.provider=@provider AND a.status='active'
  AND (a.expires_at IS NULL OR a.expires_at>SYSDATETIME())) AS available_quota,
 (SELECT COALESCE(SUM(CEILING(CONVERT(DECIMAL(38,6),l.issued_tokens-l.consumed_tokens-l.refunded_tokens)
   *p.required_upstream_tokens/d.tokens_per_unit)),0)
  FROM dbo.OrderTokenLots l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id
  JOIN dbo.Products p ON p.product_id=d.product_id WHERE p.model_provider=@provider) AS outstanding_upstream;
GO
-- 订单完成规则：数据库状态值仍为 paid，文档与测试记录统一称“已完成（paid）”。状态改为已完成（paid）时检查明细、商品、数量、
-- 金额与可售余量；已完成（paid）、refunded、partially_refunded 的订单再次被设为 paid 视为重复完成。
-- 全部按集合判断，一条 UPDATE 同时完成多张订单时逐单检查，任一不满足则整条语句回滚。
CREATE TRIGGER dbo.trg_W11_OrderCompletionRules ON dbo.Orders AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF NOT EXISTS(SELECT 1 FROM inserted WHERE status='paid') RETURN;
 IF NOT UPDATE(status) AND EXISTS(SELECT 1 FROM deleted) RETURN;
 DECLARE @done TABLE(order_id INT PRIMARY KEY, old_status VARCHAR(24) NULL,
  total_amount DECIMAL(10,2) NOT NULL, total_tokens BIGINT NOT NULL);
 INSERT @done SELECT i.order_id,d.status,i.total_amount,i.total_tokens
 FROM inserted i LEFT JOIN deleted d ON d.order_id=i.order_id WHERE i.status='paid';
 IF EXISTS(SELECT 1 FROM @done WHERE old_status IN ('paid','refunded','partially_refunded'))
  THROW 54401,'Order is already completed and cannot be completed again',1;
 IF EXISTS(SELECT 1 FROM @done WHERE old_status IS NULL OR old_status<>'pending')
  THROW 54402,'Only a pending order can be completed',1;
 IF EXISTS(SELECT 1 FROM @done x WHERE NOT EXISTS(SELECT 1 FROM dbo.OrderDetails d WHERE d.order_id=x.order_id))
  THROW 54403,'Order without details cannot be completed',1;
 IF EXISTS(SELECT 1 FROM @done x JOIN dbo.OrderDetails d ON d.order_id=x.order_id
   LEFT JOIN dbo.Products p ON p.product_id=d.product_id
   WHERE p.product_id IS NULL OR d.quantity<=0 OR d.total_tokens<=0)
  THROW 54404,'Order detail has a missing product or non-positive quantity',1;
 IF EXISTS(SELECT 1 FROM @done x CROSS APPLY (SELECT SUM(d.subtotal) amount,SUM(d.total_tokens) tokens
   FROM dbo.OrderDetails d WHERE d.order_id=x.order_id) s
   WHERE s.amount<>x.total_amount OR s.tokens<>x.total_tokens)
  THROW 54405,'Order amount or tokens do not match its details',1;
 -- 本次完成的订单按供应商汇总上游需求（份数×每份上游消耗）；它们的批次在状态更新之后才发放，不计入已售未消费量。
 IF EXISTS(SELECT 1 FROM (SELECT p.model_provider provider,SUM(CONVERT(DECIMAL(38,0),d.quantity)*p.required_upstream_tokens) demand
    FROM @done x JOIN dbo.OrderDetails d ON d.order_id=x.order_id
    JOIN dbo.Products p ON p.product_id=d.product_id GROUP BY p.model_provider) need
   CROSS APPLY w11.fn_ProviderSellable(need.provider) s
   WHERE need.demand>s.available_quota-s.outstanding_upstream)
  THROW 54406,'Insufficient sellable upstream inventory for this order',1;
END;
GO
-- Orders 上原有 trg_W5_OrdersFinalized 也核对明细与金额；让本触发器先执行，拒绝时给出本周的明确错误号。
EXEC sys.sp_settriggerorder @triggername=N'dbo.trg_W11_OrderCompletionRules',@order=N'First',@stmttype=N'UPDATE';
EXEC sys.sp_settriggerorder @triggername=N'dbo.trg_W11_OrderCompletionRules',@order=N'First',@stmttype=N'INSERT';
GO
-- 审计对应商品：库存按上游账号保存，一条审计记录影响该账号所属供应商的全部套餐。视图按供应商把每条审计
-- 记录展开到对应商品编号（审计一行对应该供应商的每个商品各一行），不改动审计表；供应商没有商品时 product_id 为 NULL。
CREATE VIEW w11.v_InventoryAuditProduct AS
SELECT a.audit_id,a.inventory_id,a.account_id,a.provider,p.product_id,p.name AS product_name,a.operation_type,
 a.quota_before,a.quota_after,a.change_quantity,a.operated_at,a.operator,a.login_name
FROM w11.InventoryAudit a
LEFT JOIN dbo.Products p ON p.model_provider=a.provider;
GO
