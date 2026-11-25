-- Shared stock gate. Caller already owns a transaction and must acquire providers in ascending order.
CREATE OR ALTER PROCEDURE w12.usp_LockInventoryProvider @provider varchar(50)
AS
BEGIN
 SET NOCOUNT ON;
 -- Match provider columns with the database collation, then use a stable spelling
 -- because application lock resource names are always compared as binary strings.
 DECLARE @canonical varchar(50)=CASE @provider COLLATE DATABASE_DEFAULT
  WHEN 'OpenAI' THEN 'OpenAI' WHEN 'Claude' THEN 'Claude'
  WHEN 'Gemini' THEN 'Gemini' WHEN 'Other' THEN 'Other' END;
 IF @canonical IS NULL THROW 55000,'Unknown inventory provider',1;
 DECLARE @resource nvarchar(255)=CONCAT(N'TokenHub.Inventory.',@canonical),@result int;
 EXEC @result=sys.sp_getapplock @Resource=@resource,@LockMode='Exclusive',
  @LockOwner='Transaction',@LockTimeout=10000,@DbPrincipal='public';
 IF @result<0 THROW 55010,'Could not acquire inventory provider lock',1;
END;
GO
