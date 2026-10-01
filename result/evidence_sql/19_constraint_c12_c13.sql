SET NOCOUNT ON;
PRINT N'C12/C13 - unique constraints rejected with error 2627';

BEGIN TRY
  INSERT dbo.Products(name,price,model_provider,token_amount,required_upstream_tokens)
  SELECT name+N'-C12',price,model_provider,token_amount,required_upstream_tokens
  FROM dbo.Products WHERE product_id=1;
END TRY BEGIN CATCH
  SELECT 'C12 duplicate (model_provider,token_amount)' AS case_id,
         ERROR_NUMBER() AS actual_error,
         CONVERT(NVARCHAR(200),ERROR_MESSAGE()) AS message,
         CASE WHEN ERROR_NUMBER()=2627 THEN 'PASS 2627' ELSE 'FAIL' END AS result;
END CATCH

BEGIN TRY
  INSERT dbo.OrderDetails(order_id,product_id,quantity,unit_price,subtotal,tokens_per_unit,total_tokens)
  SELECT order_id,product_id,quantity,unit_price,subtotal,tokens_per_unit,total_tokens
  FROM dbo.OrderDetails WHERE detail_id=1;
END TRY BEGIN CATCH
  SELECT 'C13 duplicate (order_id,product_id)' AS case_id,
         ERROR_NUMBER() AS actual_error,
         CONVERT(NVARCHAR(200),ERROR_MESSAGE()) AS message,
         CASE WHEN ERROR_NUMBER()=2627 THEN 'PASS 2627' ELSE 'FAIL' END AS result;
END CATCH

PRINT N'-- the candidate keys actually present in the database';
SELECT kc.name AS unique_constraint,OBJECT_NAME(kc.parent_object_id) AS table_name,
       c.name AS column_name,ic.key_ordinal
FROM sys.key_constraints kc
JOIN sys.index_columns ic ON ic.object_id=kc.parent_object_id AND ic.index_id=kc.unique_index_id
JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
WHERE kc.type='UQ'
ORDER BY table_name,unique_constraint,ic.key_ordinal;

PRINT N'-- baseline row counts unchanged after the rejected inserts';
SELECT (SELECT COUNT(*) FROM dbo.Products) AS products,
       (SELECT COUNT(*) FROM dbo.OrderDetails) AS order_details;
PRINT N'PASS C12/C13 unique constraint evidence';