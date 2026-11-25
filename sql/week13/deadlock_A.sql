-- 逐段选中执行；切勿一次执行整份文件。每轮顺序和重置见 README。
-- step: A1
BEGIN TRAN;
UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity-2 WHERE product_id=1;
GO
-- step: A2
UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity-2 WHERE product_id=2;
UPDATE w13lab.OrderCase SET status='paid' WHERE id=1;
COMMIT;
