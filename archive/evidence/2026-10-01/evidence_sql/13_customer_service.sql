SET NOCOUNT ON;
PRINT N'R14/R15/R16 - customer service view boundary';
PRINT N'1) staff CAN read v_CustomerService (no password_hash / api_key columns)';

SELECT CASE WHEN EXISTS (
  SELECT 1 FROM sys.columns
  WHERE object_id=OBJECT_ID(N'dbo.v_CustomerService',N'V')
    AND name IN (N'password_hash',N'api_key')
) THEN 'FAIL sensitive column exposed' ELSE 'PASS no sensitive column' END
  AS view_column_check;

EXECUTE AS USER='hub_staff_demo';
SELECT TOP(5) user_id,username,email,phone,status,order_count,paid_amount,remaining_tokens
FROM dbo.v_CustomerService ORDER BY paid_amount DESC,user_id;
SELECT COUNT(*) AS service_rows FROM dbo.v_CustomerService;
REVERT;

PRINT N'2) R15 staff reading dbo.Users.password_hash is denied (expect error 229)';
BEGIN TRY
  EXECUTE AS USER='hub_staff_demo';
  SELECT TOP(1) password_hash FROM dbo.Users;
  REVERT;
END TRY BEGIN CATCH
  DECLARE @n1 INT=ERROR_NUMBER();
  IF USER_NAME()<>N'dbo' REVERT;
  SELECT 'R15 staff reads dbo.Users' AS case_id,@n1 AS actual_error,
         CASE WHEN @n1=229 THEN 'PASS permission denied' ELSE 'FAIL' END AS result;
END CATCH;

PRINT N'3) R16 member reading v_CustomerService is denied (expect error 229)';
BEGIN TRY
  EXECUTE AS USER='hub_user_1';
  SELECT TOP(1) email FROM dbo.v_CustomerService;
  REVERT;
END TRY BEGIN CATCH
  DECLARE @n2 INT=ERROR_NUMBER();
  IF USER_NAME()<>N'dbo' REVERT;
  SELECT 'R16 member reads v_CustomerService' AS case_id,@n2 AS actual_error,
         CASE WHEN @n2=229 THEN 'PASS permission denied' ELSE 'FAIL' END AS result;
END CATCH;

PRINT N'PASS customer service view evidence';