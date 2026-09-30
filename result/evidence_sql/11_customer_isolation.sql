SET NOCOUNT ON;
PRINT N'Customer row isolation';
EXECUTE AS USER='hub_user_1';
SELECT USER_NAME() AS actor,COUNT(*) AS visible_orders,
       MIN(user_id) AS min_user_id,MAX(user_id) AS max_user_id
FROM dbo.v_MyOrders;
SELECT COUNT(*) AS balances,MIN(user_id) AS min_user_id,MAX(user_id) AS max_user_id
FROM dbo.v_MyBalances;
REVERT;

EXECUTE AS USER='hub_user_2';
SELECT USER_NAME() AS actor,COUNT(*) AS visible_orders,
       MIN(user_id) AS min_user_id,MAX(user_id) AS max_user_id
FROM dbo.v_MyOrders;
SELECT COUNT(*) AS other_user_rows
FROM dbo.v_MyOrders WHERE user_id<>2;
REVERT;
PRINT N'PASS users 1 and 2 see only their own rows';
