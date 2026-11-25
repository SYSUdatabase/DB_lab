-- Shared stock gate. Caller already owns a transaction and must acquire providers in ascending order.
CREATE OR ALTER PROCEDURE w12.usp_LockInventoryProvider @provider varchar(50)
AS
BEGIN
 SET NOCOUNT ON;
 DECLARE @resource nvarchar(255)=CONCAT(N'TokenHub.Inventory.',@provider),@result int;
 EXEC @result=sys.sp_getapplock @Resource=@resource,@LockMode='Exclusive',
  @LockOwner='Transaction',@LockTimeout=15000,@DbPrincipal='public';
 IF @result<0 THROW 55009,'Could not acquire inventory provider lock',1;
END;
GO
