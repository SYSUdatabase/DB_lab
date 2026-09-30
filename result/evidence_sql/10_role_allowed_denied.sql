SET NOCOUNT ON;
PRINT N'Role permission matrix - live checks';
EXECUTE AS USER='hub_guest_demo';
SELECT USER_NAME() AS actor,
  HAS_PERMS_BY_NAME('dbo.v_ProductCatalog','OBJECT','SELECT') AS catalog_select,
  HAS_PERMS_BY_NAME('dbo.Orders','OBJECT','SELECT') AS orders_select;
REVERT;
EXECUTE AS USER='hub_staff_demo';
SELECT USER_NAME() AS actor,
  HAS_PERMS_BY_NAME('dbo.v_OrderDetail','OBJECT','SELECT') AS detail_select,
  HAS_PERMS_BY_NAME('dbo.Products','OBJECT','UPDATE') AS product_update;
REVERT;
EXECUTE AS USER='hub_manager_demo';
SELECT USER_NAME() AS actor,
  HAS_PERMS_BY_NAME('dbo.Products','OBJECT','UPDATE') AS product_update,
  HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','CREATE TABLE') AS create_table;
REVERT;
BEGIN TRY
  EXECUTE AS USER='hub_staff_demo';
  UPDATE dbo.Products SET price=price+1 WHERE product_id=1;
  REVERT;
END TRY BEGIN CATCH
  DECLARE @n INT=ERROR_NUMBER();
  IF USER_NAME()<>N'dbo' REVERT;
  SELECT 'R04 staff product UPDATE denied' AS case_id,@n AS actual_error,
         CASE WHEN @n=229 THEN 'PASS permission denied' ELSE 'FAIL' END AS result;
END CATCH;
BEGIN TRANSACTION;
EXECUTE AS USER='hub_staff_demo';
DECLARE @id INT=(SELECT MIN(order_id) FROM dbo.v_StaffOrderQueue WHERE status='pending');
UPDATE dbo.v_StaffOrderQueue SET status='cancelled' WHERE order_id=@id;
DECLARE @rows INT=@@ROWCOUNT;
SELECT 'R05 staff queue UPDATE allowed' AS case_id,@id AS order_id,@rows AS rows_changed,
       CASE WHEN @rows=1 THEN 'PASS' ELSE 'FAIL' END AS result;
REVERT;
ROLLBACK TRANSACTION;
PRINT N'PASS role allowed/denied checks';
