USE TokenHubDB_Week3;
GO

WITH d AS (
    SELECT order_id, SUM(subtotal) AS detail_amount, SUM(total_tokens) AS detail_tokens
    FROM dbo.OrderDetails GROUP BY order_id
)
SELECT COUNT(*) AS order_mismatch
FROM dbo.Orders o
JOIN d ON d.order_id = o.order_id
WHERE o.total_amount <> d.detail_amount
   OR o.total_tokens <> d.detail_tokens;
GO

WITH l AS (
    SELECT account_id, SUM(change_amount) AS log_balance
    FROM dbo.InventoryLog GROUP BY account_id
)
SELECT COUNT(*) AS inventory_mismatch
FROM dbo.UpstreamAccount a
JOIN dbo.Inventory i ON i.account_id = a.account_id
JOIN l ON l.account_id = a.account_id
WHERE i.current_quota <> a.total_quota - a.used_quota
   OR i.current_quota <> l.log_balance;
GO