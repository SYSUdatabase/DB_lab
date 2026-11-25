-- 逐段选中执行；切勿一次执行整份文件。每轮顺序和重置见 README。
-- step: A1
BEGIN TRY
 BEGIN TRAN;
 UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity-2 WHERE product_id=1;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
GO
-- step: A2
BEGIN TRY
 IF XACT_STATE()<>1 THROW 57105,'Start A1 before completing the order',1;
 UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity-2 WHERE product_id=2;
 UPDATE w13lab.OrderCase SET status='paid' WHERE id=1;
 COMMIT;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
