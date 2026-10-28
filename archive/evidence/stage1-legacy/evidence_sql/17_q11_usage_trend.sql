USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
PRINT N'Q11 - usage trend from UsageSummary (daily)';
SELECT TOP 14 period_start AS usage_day,
       SUM(total_tokens_used) AS tokens_used,
       SUM(total_upstream_consumed) AS upstream_consumed,
       SUM(request_count) AS requests
FROM dbo.UsageSummary WHERE period_type='daily'
GROUP BY period_start ORDER BY period_start DESC;

PRINT N'Q11 - monthly buckets';
SELECT period_start AS month_start,period_end AS month_end,
       SUM(total_tokens_used) AS tokens_used,
       SUM(total_upstream_consumed) AS upstream_consumed,
       SUM(request_count) AS requests
FROM dbo.UsageSummary WHERE period_type='monthly'
GROUP BY period_start,period_end ORDER BY period_start;

PRINT N'Full 83-day daily aggregation equals full monthly aggregation; displayed TOP 14 is a separate window';
SELECT SUM(total_tokens_used) AS daily_tokens,
       (SELECT SUM(total_tokens_used) FROM dbo.UsageSummary WHERE period_type='monthly')
         AS monthly_tokens
FROM dbo.UsageSummary WHERE period_type='daily';

IF (SELECT SUM(total_tokens_used) FROM dbo.UsageSummary WHERE period_type='daily')<>(SELECT SUM(total_tokens_used) FROM dbo.UsageSummary WHERE period_type='monthly') THROW 51469,N'Full-period trend mismatch',1;
PRINT N'PASS Q11 full-period trend reconciliation';