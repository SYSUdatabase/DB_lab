-- 逐段选中执行；切勿一次执行整份文件。每轮顺序和重置见 README。
-- step: B1_reverse
SET DEADLOCK_PRIORITY LOW;
BEGIN TRAN;
UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity+5 WHERE product_id=2;
GO
-- step: B2_reverse
BEGIN TRY
 UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity+5 WHERE product_id=1;
 UPDATE w13lab.RestockCase SET status='completed',actual=5 WHERE id=1;
 COMMIT;
 SELECT 0 AS error_number,@@TRANCOUNT AS trancount;
END TRY
BEGIN CATCH
 IF ERROR_NUMBER()<>1205 THROW;
 DECLARE @count int=@@TRANCOUNT,@state int=XACT_STATE();
 IF @@TRANCOUNT>0 ROLLBACK;
 SELECT ERROR_NUMBER() AS error_number,@@TRANCOUNT AS trancount,
  @count AS caught_trancount,@state AS caught_xact_state;
END CATCH;
SET DEADLOCK_PRIORITY NORMAL;
GO
-- step: B1_ordered
BEGIN TRAN;
UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity+5 WHERE product_id=1;
UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity+5 WHERE product_id=2;
UPDATE w13lab.RestockCase SET status='completed',actual=5 WHERE id=1;
COMMIT;
