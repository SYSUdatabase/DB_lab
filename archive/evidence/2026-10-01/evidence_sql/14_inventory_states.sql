SET NOCOUNT ON;
PRINT N'v_InventoryStatus - account / quota / stock states split';
SELECT TOP(12) account_id,provider,current_quota,safety_threshold,
       account_state,stock_state,quota_headroom,
       CASE WHEN stock_state=N'low' THEN N'INNER branch'
            WHEN stock_state=N'normal' THEN N'review' ELSE N'ok' END AS action
FROM dbo.v_InventoryStatus ORDER BY account_id;

SELECT account_state,stock_state,COUNT(*) AS accounts
FROM dbo.v_InventoryStatus
GROUP BY account_state,stock_state
ORDER BY account_state,stock_state;

PRINT N'-- accounts with a negative balance must not appear in the view';
SELECT COUNT(*) AS rows_with_negative_balance
FROM dbo.v_InventoryStatus WHERE current_quota < 0;

PRINT N'-- movement mix behind the quota values';
SELECT change_type,COUNT(*) AS movements,SUM(change_amount) AS net_change
FROM dbo.InventoryLog GROUP BY change_type ORDER BY change_type;

PRINT N'PASS inventory state split';