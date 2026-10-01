SET NOCOUNT ON;
PRINT N'Q12 - inventory consumption ranking';
SELECT TOP 10 a.account_id,a.provider,a.account_name,
       SUM(CASE WHEN l.change_type='consumption' THEN -l.change_amount ELSE 0 END) AS tokens_consumed,
       SUM(CASE WHEN l.change_type='purchase'    THEN  l.change_amount ELSE 0 END) AS tokens_purchased,
       SUM(CASE WHEN l.change_type='restock'     THEN  l.change_amount ELSE 0 END) AS tokens_restocked,
       COUNT(*) AS movements
FROM dbo.InventoryLog l JOIN dbo.UpstreamAccount a ON a.account_id=l.account_id
GROUP BY a.account_id,a.provider,a.account_name
ORDER BY tokens_consumed DESC;

PRINT N'-- movement mix: replenishment must not count as consumption';
SELECT change_type,COUNT(*) AS movements,SUM(change_amount) AS net_change
FROM dbo.InventoryLog GROUP BY change_type ORDER BY change_type;

PRINT N'-- top consumer detail (6 most recent movements)';
DECLARE @top INT=(SELECT TOP(1) l.account_id FROM dbo.InventoryLog l
  GROUP BY l.account_id
  ORDER BY SUM(CASE WHEN l.change_type='consumption' THEN -l.change_amount ELSE 0 END) DESC);
PRINT CONCAT('top consumer account=',@top);
SELECT TOP(6) l.log_id,l.change_type,l.change_amount,l.reason
FROM dbo.InventoryLog l WHERE l.account_id=@top
ORDER BY l.log_id DESC;

PRINT N'PASS Q12 consumption ranking';