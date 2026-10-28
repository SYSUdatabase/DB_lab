USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
CREATE TABLE #ConstraintCases (
    case_id VARCHAR(4) PRIMARY KEY,
    statement_sql NVARCHAR(MAX) NOT NULL,
    expected_error INT NOT NULL,
    expected_name SYSNAME NULL,
    cleanup_sql NVARCHAR(MAX) NOT NULL
);
INSERT #ConstraintCases VALUES
('C01',N'INSERT dbo.Products(name,price,model_provider,token_amount,required_upstream_tokens) VALUES(N''W4默认值验证'',1,''Other'',900001,900001); IF NOT EXISTS(SELECT 1 FROM dbo.Products WHERE name=N''W4默认值验证'' AND status=''active'' AND created_at IS NOT NULL AND description IS NULL) THROW 51101,N''Default assertion failed'',1;',0,NULL,N''),
('C02',N'INSERT dbo.Orders(user_id,total_amount,total_tokens) VALUES(1,0,0); DECLARE @new_id INT=SCOPE_IDENTITY(); IF NOT EXISTS(SELECT 1 FROM dbo.Orders WHERE order_id=@new_id AND status=''pending'' AND paid_at IS NULL) THROW 51102,N''Order default assertion failed'',1;',0,NULL,N''),
('C03',N'SET IDENTITY_INSERT dbo.Orders ON; INSERT dbo.Orders(order_id,user_id,total_amount,total_tokens) VALUES(1,1,0,0);',2627,N'PK_Orders',N'SET IDENTITY_INSERT dbo.Orders OFF;'),
('C04',N'INSERT dbo.Users(username,password_hash,email) VALUES(''user001'',REPLICATE(''x'',60),''w4-unique@example.edu'');',2627,N'UQ_Users_username',N''),
('C05',N'INSERT dbo.Orders(user_id,total_amount,total_tokens) VALUES(999999,0,0);',547,N'FK_Orders_Users',N''),
('C06',N'INSERT dbo.Products(name,price,model_provider,token_amount,required_upstream_tokens) VALUES(N''W4负价格'',-1,''Other'',900002,900002);',547,N'CK_Products_price',N''),
('C07',N'INSERT dbo.Products(name,price,model_provider,token_amount,required_upstream_tokens) VALUES(NULL,1,''Other'',900003,900003);',515,NULL,N''),
('C08',N'UPDATE dbo.OrderDetails SET subtotal=subtotal+0.01 WHERE detail_id=1;',547,N'CK_OrderDetails_subtotal_formula',N''),
('C09',N'UPDATE dbo.OrderDetails SET total_tokens=total_tokens+1 WHERE detail_id=1;',547,N'CK_OrderDetails_tokens_formula',N''),
('C10',N'UPDATE dbo.Orders SET paid_at=NULL WHERE order_id=(SELECT MIN(order_id) FROM dbo.Orders WHERE status=''paid'');',547,N'CK_Orders_payment_time',N''),
('C11',N'DELETE dbo.Users WHERE user_id=1;',547,NULL,N''),
('C12',N'INSERT dbo.Products(name,price,model_provider,token_amount,required_upstream_tokens) SELECT name+N''-C12'',price,model_provider,token_amount,required_upstream_tokens FROM dbo.Products WHERE product_id=1;',2627,N'UQ_Products_provider_tokens',N''),
('C13',N'INSERT dbo.OrderDetails(order_id,product_id,quantity,unit_price,subtotal,tokens_per_unit,total_tokens) SELECT order_id,product_id,quantity,unit_price,subtotal,tokens_per_unit,total_tokens FROM dbo.OrderDetails WHERE detail_id=1;',2627,N'UQ_OrderDetails_order_product',N''),
('C14',N'UPDATE dbo.Roles SET permissions=N''not-json'' WHERE role_name=''staff'';',547,N'CK_Roles_permissions_json',N'');
DELETE FROM #ConstraintCases WHERE case_id NOT IN ('C12','C13');
GO
DECLARE @id VARCHAR(4),@stmt NVARCHAR(MAX),@want INT,@name SYSNAME,
        @cleanup NVARCHAR(MAX),@got INT,@msg NVARCHAR(4000),@pass_count INT=0;
DECLARE cases CURSOR LOCAL FAST_FORWARD FOR
SELECT case_id,statement_sql,expected_error,expected_name,cleanup_sql
FROM #ConstraintCases ORDER BY case_id;
OPEN cases;
FETCH NEXT FROM cases INTO @id,@stmt,@want,@name,@cleanup;
WHILE @@FETCH_STATUS=0
BEGIN
    SELECT @got=0,@msg=N'';
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC sys.sp_executesql @stmt;
        ROLLBACK TRANSACTION;
    END TRY
    BEGIN CATCH
        SELECT @got=ERROR_NUMBER(),@msg=ERROR_MESSAGE();
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    END CATCH;
    IF @cleanup<>N'' EXEC sys.sp_executesql @cleanup;
    IF @got<>@want OR (@name IS NOT NULL AND CHARINDEX(@name,@msg)=0)
    BEGIN
        SET @msg=CONCAT(@id,N' failed; expected=',@want,N'; actual=',@got,N'; ',@msg);
        THROW 51199,@msg,1;
    END;
    SET @pass_count+=1;
    SELECT @id AS case_id,N'PASS' AS result,@got AS actual_error,@msg AS actual_message;
    FETCH NEXT FROM cases INTO @id,@stmt,@want,@name,@cleanup;
END;
CLOSE cases;
DEALLOCATE cases;
DROP TABLE #ConstraintCases;
IF @pass_count<>2 THROW 51198,N'Expected 2 selected PASS cases',1;
IF @@TRANCOUNT<>0 THROW 51197,N'Open transaction after constraint tests',1;
PRINT N'PASS selected constraint cases';
GO
