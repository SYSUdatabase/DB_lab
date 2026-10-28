USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
PRINT N'Q10 - INNER JOIN versus LEFT JOIN row counts';
WITH paid_product AS (
    SELECT d.product_id
    FROM dbo.OrderDetails d JOIN dbo.Orders o ON o.order_id=d.order_id
    WHERE o.status='paid' GROUP BY d.product_id
)
SELECT 'products INNER JOIN' AS join_type,COUNT(*) AS rows_returned
FROM dbo.Products p JOIN paid_product s ON s.product_id=p.product_id
UNION ALL
SELECT 'products LEFT JOIN',COUNT(*)
FROM dbo.Products p LEFT JOIN paid_product s ON s.product_id=p.product_id
UNION ALL
SELECT 'members INNER JOIN',COUNT(*)
FROM dbo.Users u
JOIN (SELECT DISTINCT user_id FROM dbo.Orders WHERE status='paid') s ON s.user_id=u.user_id
UNION ALL
SELECT 'members LEFT JOIN',COUNT(*)
FROM dbo.Users u
LEFT JOIN (SELECT DISTINCT user_id FROM dbo.Orders WHERE status='paid') s ON s.user_id=u.user_id;

PRINT N'-- the INNER branch drops the products that were never ordered';
SELECT COUNT(*) AS products_total FROM dbo.Products;
SELECT COUNT(*) AS products_never_ordered
FROM dbo.Products p
WHERE NOT EXISTS (SELECT 1 FROM dbo.OrderDetails d WHERE d.product_id=p.product_id);

SELECT p.product_id,p.model_provider,p.token_amount
FROM dbo.Products p
LEFT JOIN (SELECT d.product_id FROM dbo.OrderDetails d
           JOIN dbo.Orders o ON o.order_id=d.order_id
           WHERE o.status='paid' GROUP BY d.product_id) s
  ON s.product_id=p.product_id
WHERE s.product_id IS NULL
ORDER BY p.product_id;


IF (SELECT COUNT(DISTINCT user_id) FROM dbo.Orders WHERE status='paid')<>26 OR (SELECT COUNT(*) FROM dbo.Users)<>40 THROW 51465,N'Join contrast mismatch',1;
PRINT N'PASS verified evidence result';
