-- 逐段选中执行；切勿一次执行整份文件。每轮顺序和重置见 README。
-- step: A1
BEGIN TRAN;
UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity-2 WHERE product_id=1;
-- Hold for B1 / observer.
GO
-- step: A2_commit
UPDATE w13lab.OrderCase SET status='paid' WHERE id=1;
COMMIT;
GO
-- step: A2_rollback
ROLLBACK;
