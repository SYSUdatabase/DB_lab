SET NOCOUNT ON;
BEGIN TRANSACTION;
INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,used_quota,safety_threshold,status)
VALUES('Other',N'W4_SCREENSHOT_ACCOUNT',N'DEMO_NOT_A_REAL_API_KEY_SCREENSHOT',100000,0,10000,'active');
DECLARE @a INT=SCOPE_IDENTITY();
INSERT dbo.Inventory(account_id,current_quota) VALUES(@a,100000);
PRINT N'After INSERT';
SELECT a.account_id,a.account_name,i.current_quota
FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id=a.account_id
WHERE a.account_id=@a;
UPDATE dbo.Inventory SET current_quota=current_quota-1000 WHERE account_id=@a;
PRINT N'After UPDATE';
SELECT account_id,current_quota FROM dbo.Inventory WHERE account_id=@a;
DELETE dbo.Inventory WHERE account_id=@a;
DELETE dbo.UpstreamAccount WHERE account_id=@a;
PRINT N'After DELETE';
SELECT COUNT(*) AS demo_rows FROM dbo.UpstreamAccount WHERE account_id=@a;
ROLLBACK TRANSACTION;
PRINT N'PASS Inventory CRUD; transaction rolled back';
