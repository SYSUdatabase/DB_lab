-- 确认 A/B 都已退出事务后执行，只删除本实验的简化对象。
IF DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]WebW13%' OR @@TRANCOUNT<>0
 THROW 57103,'Cleanup requires a dedicated batch and no open transaction',1;
SET XACT_ABORT ON;
IF SCHEMA_ID('w13lab') IS NOT NULL
BEGIN
 BEGIN TRAN;
 DROP TABLE IF EXISTS w13lab.Business;
 DROP TABLE w13lab.RestockCase,w13lab.OrderCase,w13lab.Stock;
 DROP SCHEMA w13lab;
 COMMIT;
END;
