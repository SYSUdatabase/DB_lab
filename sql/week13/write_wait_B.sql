-- 逐段选中执行；切勿一次执行整份文件。每轮顺序和重置见 README。
-- step: B1
BEGIN TRAN;
UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity+5 WHERE product_id=1;
UPDATE w13lab.RestockCase SET status='completed',actual=5 WHERE id=1;
COMMIT;
