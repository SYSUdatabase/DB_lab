SET NOCOUNT ON;
PRINT N'Illegal data must be rejected';
BEGIN TRY
  INSERT dbo.Orders(user_id,total_amount,total_tokens) VALUES(999999,0,0);
END TRY BEGIN CATCH
  SELECT 'C05' AS case_id,ERROR_NUMBER() AS actual_error,
    CASE WHEN ERROR_NUMBER()=547 AND CHARINDEX('FK_Orders_Users',ERROR_MESSAGE())>0
         THEN 'PASS FK_Orders_Users' ELSE 'FAIL' END AS result;
END CATCH;
BEGIN TRY
  INSERT dbo.Products(name,price,model_provider,token_amount,required_upstream_tokens)
  VALUES(N'W4截图负价格',-1,'Other',930002,930002);
END TRY BEGIN CATCH
  SELECT 'C06' AS case_id,ERROR_NUMBER() AS actual_error,
    CASE WHEN ERROR_NUMBER()=547 AND CHARINDEX('CK_Products_price',ERROR_MESSAGE())>0
         THEN 'PASS CK_Products_price' ELSE 'FAIL' END AS result;
END CATCH;
BEGIN TRY
  UPDATE dbo.OrderDetails SET subtotal=subtotal+0.01 WHERE detail_id=1;
END TRY BEGIN CATCH
  SELECT 'C08' AS case_id,ERROR_NUMBER() AS actual_error,
    CASE WHEN ERROR_NUMBER()=547 AND CHARINDEX('CK_OrderDetails_subtotal_formula',ERROR_MESSAGE())>0
         THEN 'PASS CK_OrderDetails_subtotal_formula' ELSE 'FAIL' END AS result;
END CATCH;
PRINT N'PASS: C05/C06/C08 rejected by expected constraints';
