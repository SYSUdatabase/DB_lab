-- Isolated v1.1: verify all balance/quota/log/summary deltas atomically.
:on error exit
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014' THROW 51970,'Wrong DB',1;
DECLARE @old_balance BIGINT=(SELECT remaining_tokens FROM dbo.TokenBalances WHERE user_id=1 AND model_provider='OpenAI'),
 @old_inventory BIGINT=(SELECT current_quota FROM dbo.Inventory WHERE account_id=1),
 @old_used BIGINT=(SELECT used_quota FROM dbo.UpstreamAccount WHERE account_id=1),
 @old_logs BIGINT=(SELECT COUNT_BIG(*) FROM dbo.TokenUsageLogs),
 @old_changes BIGINT=(SELECT COUNT_BIG(*) FROM dbo.InventoryLog),
 @old_periods BIGINT=(SELECT COUNT_BIG(*) FROM dbo.UsagePeriod),
 @old_summaries BIGINT=(SELECT COUNT_BIG(*) FROM dbo.UsageSummaryCore),
 @fail INT=0;
BEGIN TRY
 BEGIN TRAN;
 EXEC dbo.usp_W5_RecordUsage @user_id=1,@product_id=1,@account_id=1,
    @tokens_used=2,@upstream_tokens_used=3,@api_endpoint='w5_sandbox_probe';
 IF (SELECT remaining_tokens FROM dbo.TokenBalances WHERE user_id=1 AND model_provider='OpenAI')<>@old_balance-2
    OR (SELECT current_quota FROM dbo.Inventory WHERE account_id=1)<>@old_inventory-3
    OR (SELECT used_quota FROM dbo.UpstreamAccount WHERE account_id=1)<>@old_used+3
    OR (SELECT COUNT_BIG(*) FROM dbo.TokenUsageLogs)<>@old_logs+1
    OR (SELECT COUNT_BIG(*) FROM dbo.InventoryLog)<>@old_changes+1
    OR (SELECT COUNT_BIG(*) FROM dbo.UsagePeriod)<@old_periods
    OR (SELECT COUNT_BIG(*) FROM dbo.UsageSummaryCore)<@old_summaries
    THROW 51971,'Atomic effect missing',1;
 IF (SELECT COUNT(*) FROM dbo.UsageSummaryCore s
     JOIN dbo.Products p ON p.product_id=s.product_id
     WHERE s.user_id=1 AND p.model_provider='OpenAI'
      AND s.product_id=1 AND s.period_start IN(
          CONVERT(DATE,SYSDATETIME()),
          DATEADD(DAY,-DATEDIFF(DAY,CONVERT(DATE,'19000101'),CONVERT(DATE,SYSDATETIME()))%7,
             CONVERT(DATE,SYSDATETIME())),
          DATEFROMPARTS(YEAR(SYSDATETIME()),MONTH(SYSDATETIME()),1)
      ))<3
    THROW 51972,'Daily/weekly/monthly summaries missing',1;
 ROLLBACK;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
IF (SELECT remaining_tokens FROM dbo.TokenBalances WHERE user_id=1 AND model_provider='OpenAI')<>@old_balance
 OR (SELECT current_quota FROM dbo.Inventory WHERE account_id=1)<>@old_inventory
 OR (SELECT used_quota FROM dbo.UpstreamAccount WHERE account_id=1)<>@old_used
 OR (SELECT COUNT_BIG(*) FROM dbo.TokenUsageLogs)<>@old_logs
 OR (SELECT COUNT_BIG(*) FROM dbo.InventoryLog)<>@old_changes
 OR (SELECT COUNT_BIG(*) FROM dbo.UsageSummaryCore)<>@old_summaries
 OR (SELECT COUNT_BIG(*) FROM dbo.UsagePeriod)<>@old_periods
 THROW 51973,'Transaction rollback left changes',1;
PRINT 'PASS I06/I09 managed usage: balance, quota, logs, summaries and rollback';
BEGIN TRY
 EXEC dbo.usp_W5_RecordUsage @user_id=1,@product_id=1,@account_id=1,
      @tokens_used=2147483647,@upstream_tokens_used=3;
END TRY
BEGIN CATCH
 SET @fail=ERROR_NUMBER();
END CATCH;
IF @fail<>51956 THROW 51974,'Insufficient balance not rejected as 51956',1;
IF (SELECT COUNT_BIG(*) FROM dbo.TokenUsageLogs)<>@old_logs
 THROW 51975,'Rejected usage wrote a log',1;
IF @@TRANCOUNT<>0 THROW 51976,'Test left open transaction',1;
PRINT 'PASS I09 insufficient balance rejected with no writes';
PRINT 'PASS V11 MANAGED USAGE REGRESSION';