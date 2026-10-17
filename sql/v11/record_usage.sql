-- v1.1 new calls must use one atomic write path to prevent negative current
-- balance and to update upstream account, inventory, logs and summaries together.
-- CALL ONLY on isolated TokenHubDB_v11_Issues_20261014.
:on error exit
SET NOCOUNT ON;
IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
 THROW 51950,'Wrong database for v1.1 stored procedure',1;
IF OBJECT_ID('dbo.usp_W5_RecordUsage','P') IS NOT NULL
 THROW 51951,'Procedure exists; refuse silent overwrite',1;
GO
CREATE PROCEDURE dbo.usp_W5_RecordUsage
 @user_id INT,
 @product_id INT,
 @account_id INT,
 @tokens_used INT,
 @upstream_tokens_used INT,
 @api_endpoint VARCHAR(255)=NULL
WITH EXECUTE AS OWNER
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 IF DB_NAME()<>'TokenHubDB_v11_Issues_20261014'
  THROW 51952,'Wrong usage database',1;
 IF @tokens_used<=0 OR @upstream_tokens_used<=0
  THROW 51953,'Usage amounts must be positive',1;
 DECLARE @ts DATETIME2(0)=CONVERT(DATETIME2(0),SYSDATETIME());
 DECLARE @provider VARCHAR(50),@account_provider VARCHAR(50),@ucreated DATETIME2(0),
         @acct_created DATETIME2(0),@acct_expires DATETIME2(0),
         @bal BIGINT,@inv BIGINT,@used BIGINT,@total BIGINT,@latest DATETIME2(0),
         @log_id INT;
 BEGIN TRY
  SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
  BEGIN TRANSACTION;
  SELECT @ucreated=created_at FROM dbo.Users WITH(UPDLOCK,HOLDLOCK)
     WHERE user_id=@user_id AND status='active';
  SELECT @provider=model_provider FROM dbo.Products WITH(UPDLOCK,HOLDLOCK)
     WHERE product_id=@product_id AND status='active';
  SELECT @account_provider=provider,@acct_created=created_at,
         @acct_expires=expires_at,@used=used_quota,@total=total_quota
     FROM dbo.UpstreamAccount WITH(UPDLOCK,HOLDLOCK)
     WHERE account_id=@account_id AND status='active';
  IF @ucreated IS NULL OR @provider IS NULL OR @account_provider IS NULL
   THROW 51954,'User, product or account unavailable',1;
  IF @provider<>@account_provider OR @ts<@ucreated OR @ts<@acct_created
     OR (@acct_expires IS NOT NULL AND @ts>=@acct_expires)
   THROW 51955,'Provider, registration or account usage interval invalid',1;
  SELECT @bal=remaining_tokens FROM dbo.TokenBalances WITH(UPDLOCK,HOLDLOCK)
   WHERE user_id=@user_id AND model_provider=@provider;
  SELECT @inv=current_quota FROM dbo.Inventory WITH(UPDLOCK,HOLDLOCK)
   WHERE account_id=@account_id;
  IF @bal IS NULL OR @inv IS NULL OR @bal<@tokens_used
     OR @inv<@upstream_tokens_used OR @total-@used<@upstream_tokens_used
     OR @inv<>@total-@used
   THROW 51956,'Insufficient balance, quota or inconsistent inventory',1;
  SELECT @latest=MAX(l.used_at) FROM dbo.TokenUsageLogs l WITH(HOLDLOCK)
    JOIN dbo.Products p ON p.product_id=l.product_id
    WHERE l.user_id=@user_id AND p.model_provider=@provider;
  IF @latest IS NOT NULL AND @ts<@latest
   THROW 51957,'Out-of-order new usage event',1;
  UPDATE dbo.TokenBalances SET remaining_tokens=remaining_tokens-@tokens_used,
        updated_at=@ts WHERE user_id=@user_id AND model_provider=@provider;
  UPDATE dbo.UpstreamAccount SET used_quota=used_quota+@upstream_tokens_used,
        updated_at=@ts WHERE account_id=@account_id;
  UPDATE dbo.Inventory SET current_quota=current_quota-@upstream_tokens_used,
        last_updated_at=@ts WHERE account_id=@account_id;
  INSERT dbo.TokenUsageLogs(user_id,product_id,account_id,tokens_used,
       upstream_tokens_consumed,api_endpoint,used_at)
  VALUES(@user_id,@product_id,@account_id,@tokens_used,
       @upstream_tokens_used,@api_endpoint,@ts);
  SET @log_id=CONVERT(INT,SCOPE_IDENTITY());
  INSERT dbo.InventoryLog(account_id,change_type,change_amount,
        reference_type,reference_id,reason,operator_id,created_at)
  VALUES(@account_id,'consumption',-CONVERT(BIGINT,@upstream_tokens_used),
         NULL,NULL,N'API token usage',NULL,@ts);
  DECLARE @day DATE=CONVERT(DATE,@ts),
          @monday DATE=DATEADD(DAY,-DATEDIFF(DAY,CONVERT(DATE,'19000101'),CONVERT(DATE,@ts))%7,CONVERT(DATE,@ts)),
          @month DATE=DATEFROMPARTS(YEAR(@ts),MONTH(@ts),1);
  DECLARE @period TABLE(period_type VARCHAR(10),period_start DATE,period_end DATE,
        PRIMARY KEY(period_type,period_start));
  INSERT @period VALUES('daily',@day,@day),('weekly',@monday,DATEADD(DAY,6,@monday)),
        ('monthly',@month,EOMONTH(@month));
  INSERT dbo.UsagePeriod(period_type,period_start,period_end)
  SELECT t.period_type,t.period_start,t.period_end FROM @period t
  WHERE NOT EXISTS(SELECT 1 FROM dbo.UsagePeriod p WITH(UPDLOCK,HOLDLOCK)
        WHERE p.period_type=t.period_type AND p.period_start=t.period_start);
  UPDATE s SET s.total_tokens_used=s.total_tokens_used+@tokens_used,
     s.total_upstream_consumed=s.total_upstream_consumed+@upstream_tokens_used,
     s.request_count=s.request_count+1,s.last_updated_at=@ts
  FROM dbo.UsageSummaryCore s JOIN @period p
   ON p.period_type=s.period_type AND p.period_start=s.period_start
  WHERE s.user_id=@user_id AND s.product_id=@product_id;
  INSERT dbo.UsageSummaryCore(user_id,product_id,period_type,period_start,
         total_tokens_used,total_upstream_consumed,request_count,last_updated_at)
  SELECT @user_id,@product_id,p.period_type,p.period_start,@tokens_used,
         @upstream_tokens_used,1,@ts FROM @period p
  WHERE NOT EXISTS (
    SELECT 1 FROM dbo.UsageSummaryCore s WITH(UPDLOCK,HOLDLOCK)
     WHERE s.user_id=@user_id AND s.product_id=@product_id
      AND s.period_type=p.period_type AND s.period_start=p.period_start);
  COMMIT TRANSACTION;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  SELECT @log_id AS log_id,@provider AS model_provider,@ts AS used_at;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  THROW;
 END CATCH;
END;
GO
GRANT EXECUTE ON dbo.usp_W5_RecordUsage TO hub_manager;
PRINT 'PASS atomic managed usage procedure installed (old logs unchanged)';
GO