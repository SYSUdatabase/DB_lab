-- Read-only baseline anomalies; no credential columns queried.
SET NOCOUNT ON;
SELECT 'orders_before_registration' AS issue, COUNT_BIG(*) AS affected FROM dbo.Orders o JOIN dbo.Users u ON o.user_id=u.user_id WHERE o.created_at<u.created_at;
SELECT 'usage_before_registration' AS issue, COUNT_BIG(*) AS affected FROM dbo.TokenUsageLogs l JOIN dbo.Users u ON l.user_id=u.user_id WHERE l.used_at<u.created_at;
SELECT 'invalid_upstream_interval_or_provider' AS issue, COUNT_BIG(*) AS affected FROM dbo.TokenUsageLogs l
 JOIN dbo.UpstreamAccount a ON a.account_id=l.account_id
 JOIN dbo.Products p ON p.product_id=l.product_id
 WHERE l.used_at<a.created_at OR (a.expires_at IS NOT NULL AND l.used_at>=a.expires_at) OR a.provider<>p.model_provider;
WITH events AS(
 SELECT o.user_id,p.model_provider,o.paid_at event_time,0 AS event_kind,
 d.detail_id event_id,CONVERT(BIGINT,d.total_tokens) AS delta
 FROM dbo.Orders o JOIN dbo.OrderDetails d ON d.order_id=o.order_id
 JOIN dbo.Products p ON p.product_id=d.product_id WHERE o.status='paid'
 UNION ALL
 SELECT l.user_id,p.model_provider,l.used_at,1,l.log_id,-CONVERT(BIGINT,l.tokens_used)
 FROM dbo.TokenUsageLogs l JOIN dbo.Products p ON p.product_id=l.product_id
), history AS(
 SELECT SUM(delta) OVER(PARTITION BY user_id,model_provider
 ORDER BY event_time,event_kind,event_id ROWS UNBOUNDED PRECEDING) AS running_balance FROM events
) SELECT 'negative_historical_balance_events' AS issue,COUNT_BIG(*) AS affected
  FROM history WHERE running_balance<0;
