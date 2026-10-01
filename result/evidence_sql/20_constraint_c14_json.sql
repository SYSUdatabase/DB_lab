SET NOCOUNT ON;
PRINT N'C14 - Roles.permissions JSON CHECK constraint';

SELECT name AS check_constraint,OBJECT_NAME(parent_object_id) AS table_name,definition,is_disabled
FROM sys.check_constraints
WHERE name IN (N'CK_Roles_permissions_json',N'CK_Users_email_format')
ORDER BY name;

BEGIN TRY
  UPDATE dbo.Roles SET permissions=N'not-json' WHERE role_name=N'staff';
END TRY BEGIN CATCH
  SELECT 'C14 invalid JSON in Roles.permissions' AS case_id,
         ERROR_NUMBER() AS actual_error,
         CONVERT(NVARCHAR(200),ERROR_MESSAGE()) AS message,
         CASE WHEN ERROR_NUMBER()=547 THEN 'PASS 547' ELSE 'FAIL' END AS result;
END CATCH

PRINT N'-- the stored value must still be valid JSON';
SELECT role_name,permissions,ISJSON(permissions) AS is_valid_json
FROM dbo.Roles ORDER BY role_id;

PRINT N'PASS C14 JSON check constraint evidence';