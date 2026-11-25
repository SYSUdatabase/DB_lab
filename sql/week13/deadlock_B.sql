-- 逐段选中执行；切勿一次执行整份文件。每轮顺序和重置见 README。
-- step: B1_reverse
BEGIN TRY
 SET DEADLOCK_PRIORITY LOW;
 BEGIN TRAN;
 UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity+5 WHERE product_id=2;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 SET DEADLOCK_PRIORITY NORMAL;
 THROW;
END CATCH;
GO
-- step: B2_reverse
BEGIN TRY
 IF XACT_STATE()<>1 THROW 57105,'Start B1_reverse before requesting P',1;
 UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity+5 WHERE product_id=1;
 UPDATE w13lab.RestockCase SET status='completed',actual=5 WHERE id=1;
 COMMIT;
 SELECT 0 AS error_number,@@TRANCOUNT AS trancount;
END TRY
BEGIN CATCH
 DECLARE @count int=@@TRANCOUNT,@state int=XACT_STATE();
 IF XACT_STATE()<>0 ROLLBACK;
 SET DEADLOCK_PRIORITY NORMAL;
 IF ERROR_NUMBER()<>1205 THROW;
 SELECT ERROR_NUMBER() AS error_number,@@TRANCOUNT AS trancount,
  @count AS caught_trancount,@state AS caught_xact_state;
END CATCH;
SET DEADLOCK_PRIORITY NORMAL;
GO
-- step: B1_ordered
BEGIN TRY
 BEGIN TRAN;
 UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity+5 WHERE product_id=1;
 UPDATE w13lab.Stock WITH(ROWLOCK) SET quantity=quantity+5 WHERE product_id=2;
 UPDATE w13lab.RestockCase SET status='completed',actual=5 WHERE id=1;
 COMMIT;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
