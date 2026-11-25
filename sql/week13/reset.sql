-- 只在 A/B 完成并确认两者 @@TRANCOUNT=0 后执行。
IF DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]WebW13%' OR @@TRANCOUNT<>0
 THROW 57102,'Reset requires a dedicated batch and no open transaction',1;
SET XACT_ABORT ON;
BEGIN TRAN;
UPDATE w13lab.Stock SET quantity=CASE product_id WHEN 1 THEN 10 ELSE 8 END;
UPDATE w13lab.OrderCase SET status='pending';
UPDATE w13lab.RestockCase SET status='pending',actual=NULL;
COMMIT;
