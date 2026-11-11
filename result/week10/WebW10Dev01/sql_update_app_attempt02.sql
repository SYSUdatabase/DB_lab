SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE app.Week10
 @token_hash VARBINARY(32),@operation VARCHAR(50),@payload NVARCHAR(MAX)=N'{}'
WITH EXECUTE AS OWNER AS
BEGIN
 SET NOCOUNT ON;
 SET ANSI_NULLS ON;
 SET ANSI_WARNINGS ON;
 SET ANSI_PADDING ON;
 SET ARITHABORT ON;
 SET CONCAT_NULL_YIELDS_NULL ON;
 SET NUMERIC_ROUNDABORT OFF;
 SET XACT_ABORT ON;
 IF @payload IS NULL OR ISJSON(@payload)<>1 OR LEFT(LTRIM(@payload),1)<>'{' THROW 56000,'JSON object required',1;
 DECLARE @role VARCHAR(50),@employee INT,@user INT,@data NVARCHAR(MAX),@items NVARCHAR(MAX);
 SELECT @role=CASE WHEN u.user_id IS NOT NULL THEN 'customer' ELSE r.role_name END,@employee=s.employee_id,@user=s.user_id
 FROM app.Sessions s WITH(HOLDLOCK)
 LEFT JOIN dbo.Users u ON u.user_id=s.user_id AND u.status='active'
 LEFT JOIN dbo.Employees e ON e.employee_id=s.employee_id AND e.status='active'
 LEFT JOIN dbo.Roles r ON r.role_id=e.role_id AND r.role_name IN('admin','staff')
 WHERE DATALENGTH(@token_hash)=32 AND s.token_hash=@token_hash AND s.revoked_at IS NULL
 AND s.expires_at>SYSDATETIME() AND (u.user_id IS NOT NULL OR r.role_id IS NOT NULL);
 IF @role IS NULL THROW 56001,'Authentication required',1;
 IF @role NOT IN('admin','staff') THROW 56003,'Employee required',1;
 IF @operation IN('inventory.adjustments.create','inventory.adjustments.list') AND @role<>'admin'
  THROW 56003,'Administrator required',1;
 IF EXISTS(SELECT 1 FROM OPENJSON(@payload) WHERE [key] IN('operator_id','employee_id','role','user_id','discount_rate','discount_amount','subtotal','unit_price','pricing_rule_version'))
  THROW 56000,'Actor and pricing fields are server controlled',1;
 -- Treat every operation payload as a closed object. OPENJSON retains types and duplicate keys.
 IF EXISTS(SELECT 1 FROM OPENJSON(@payload) GROUP BY [key] COLLATE Latin1_General_100_BIN2 HAVING COUNT(*)>1)
  THROW 56000,'Duplicate payload fields are invalid',1;
 IF EXISTS(SELECT 1 FROM OPENJSON(@payload) WHERE NOT (
   (@operation='reports.sales' AND [key] COLLATE Latin1_General_100_BIN2 IN('start_date','end_date'))
   OR (@operation='restocks.recommendation' AND [key] COLLATE Latin1_General_100_BIN2 IN('product_id','account_id','minimum_quota','target_quota'))
   OR (@operation='inventory.adjustments.create' AND [key] COLLATE Latin1_General_100_BIN2 IN('product_id','account_id','change_amount','reason','operation_key'))
   OR (@operation='inventory.adjustments.list' AND [key] COLLATE Latin1_General_100_BIN2 IN('product_id','account_id','page','page_size'))))
  THROW 56000,'Unsupported payload field',1;
 IF EXISTS(SELECT 1 FROM OPENJSON(@payload) WHERE
   ([key] IN('start_date','end_date','reason','operation_key') AND [type]<>1)
   OR ([key] IN('product_id','account_id','change_amount','target_quota','page','page_size') AND [type] NOT IN(1,2))
   OR ([key]='minimum_quota' AND [type] NOT IN(0,1,2)))
  THROW 56000,'Payload field has an invalid JSON type',1;
 DECLARE @pid INT=TRY_CONVERT(INT,JSON_VALUE(@payload,'$.product_id')),
 @aid INT=TRY_CONVERT(INT,JSON_VALUE(@payload,'$.account_id'));
 IF @operation='reports.sales'
 BEGIN
  DECLARE @start_text NVARCHAR(4000)=JSON_VALUE(@payload,'$.start_date'),@end_text NVARCHAR(4000)=JSON_VALUE(@payload,'$.end_date'),
   @start DATE,@end DATE;
  SET @start=TRY_CONVERT(DATE,@start_text,23);
  SET @end=TRY_CONVERT(DATE,@end_text,23);
  IF @start IS NULL OR @end IS NULL OR @start_text<>CONVERT(NVARCHAR(10),@start,23)
   OR @end_text<>CONVERT(NVARCHAR(10),@end,23) OR DATALENGTH(@start_text)<>20 OR DATALENGTH(@end_text)<>20
   THROW 56000,'ISO dates required',1;
  EXEC w10.usp_SalesStatistics @start,@end,@emit_result=0,@app_data=@data OUTPUT;
 END
 ELSE IF @operation='restocks.recommendation'
 BEGIN
  DECLARE @minimum BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@payload,'$.minimum_quota')),
   @target BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@payload,'$.target_quota')),@recommended BIGINT;
  IF @pid IS NULL OR @aid IS NULL OR @target IS NULL
   OR (JSON_VALUE(@payload,'$.minimum_quota') IS NOT NULL AND @minimum IS NULL)
   THROW 56000,'Valid product, account and quota values required',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Products WHERE product_id=@pid)
   OR NOT EXISTS(SELECT 1 FROM dbo.UpstreamAccount WHERE account_id=@aid) THROW 56004,'Product or account missing',1;
  SET @recommended=w10.fn_ReplenishmentQuantity(@pid,@aid,@minimum,@target);
  IF @recommended IS NULL THROW 56000,'Invalid replenishment parameters or unavailable inventory pair',1;
  SET @data=(SELECT @recommended recommended_quantity FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 END
 ELSE IF @operation='inventory.adjustments.create'
 BEGIN
  DECLARE @change BIGINT=TRY_CONVERT(BIGINT,JSON_VALUE(@payload,'$.change_amount')),
   @reason NVARCHAR(MAX)=JSON_VALUE(@payload,'$.reason'),
   @key_text NVARCHAR(4000)=JSON_VALUE(@payload,'$.operation_key'),@key UNIQUEIDENTIFIER,@adjustment BIGINT;
  SET @key=TRY_CONVERT(UNIQUEIDENTIFIER,@key_text);
  IF @key IS NULL OR DATALENGTH(@key_text)<>72 THROW 56000,'Canonical operation UUID required',1;
  EXEC w10.usp_AdjustInventory @pid,@aid,@change,@reason,@employee,@key,@emit_result=0,@app_result_id=@adjustment OUTPUT;
  SET @data=(SELECT * FROM w10.InventoryAdjustments WHERE adjustment_id=@adjustment FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 END
 ELSE IF @operation='inventory.adjustments.list'
 BEGIN
  DECLARE @page INT=COALESCE(TRY_CONVERT(INT,JSON_VALUE(@payload,'$.page')),1),
   @page_size INT=COALESCE(TRY_CONVERT(INT,JSON_VALUE(@payload,'$.page_size')),20),@total BIGINT;
  IF @page<1 OR @page>1000000 OR @page_size<1 OR @page_size>100
   OR (JSON_VALUE(@payload,'$.page') IS NOT NULL AND TRY_CONVERT(INT,JSON_VALUE(@payload,'$.page')) IS NULL)
   OR (JSON_VALUE(@payload,'$.page_size') IS NOT NULL AND TRY_CONVERT(INT,JSON_VALUE(@payload,'$.page_size')) IS NULL)
   OR (JSON_VALUE(@payload,'$.account_id') IS NOT NULL AND @aid IS NULL)
   OR (JSON_VALUE(@payload,'$.product_id') IS NOT NULL AND @pid IS NULL)
   THROW 56000,'Invalid adjustment filter or pagination',1;
  SET @items=(SELECT * FROM w10.InventoryAdjustments WHERE (@aid IS NULL OR account_id=@aid) AND (@pid IS NULL OR product_id=@pid)
   ORDER BY adjustment_id DESC OFFSET (@page-1)*@page_size ROWS FETCH NEXT @page_size ROWS ONLY FOR JSON PATH);
  SELECT @total=COUNT_BIG(*) FROM w10.InventoryAdjustments WHERE (@aid IS NULL OR account_id=@aid) AND (@pid IS NULL OR product_id=@pid);
  SET @data=(SELECT JSON_QUERY(@items) items,@total total,@page page,@page_size page_size FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);
 END
 ELSE THROW 56000,'Unknown week10 operation',1;
 SELECT @data data;
END;
GO
GRANT EXECUTE ON app.Week10 TO app_runtime;
GO


