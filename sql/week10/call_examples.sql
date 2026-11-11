:on error exit
USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
-- SELECT calls are read-only. Invalid dates return an empty sales TVF.
SELECT * FROM w10.fn_OrderDiscount(99.99);
SELECT * FROM w10.fn_OrderDiscount(100);
SELECT * FROM w10.fn_OrderDiscount(500);
SELECT * FROM w10.fn_OrderDiscount(NULL);
SELECT * FROM w10.fn_SalesSummary('20260101','20261231');
EXEC w10.usp_SalesStatistics @start_date='20260101',@end_date='20261231';
GO
-- Capture a matching current pair rather than relying on seed IDs.
DECLARE @product INT,@account INT,@current BIGINT,@minimum BIGINT,@target BIGINT;
SELECT TOP(1) @product=p.product_id,@account=a.account_id,@current=i.current_quota,@minimum=a.safety_threshold
 FROM dbo.Products p JOIN dbo.UpstreamAccount a ON a.provider=p.model_provider
 JOIN dbo.Inventory i ON i.account_id=a.account_id
 WHERE a.status='active' AND a.created_at<=SYSDATETIME()
 AND (a.expires_at IS NULL OR a.expires_at>SYSDATETIME())
 AND i.current_quota=a.total_quota-a.used_quota ORDER BY p.product_id,a.account_id;
SET @target=CASE WHEN @minimum>@current THEN @minimum ELSE @current END;
SELECT @product product_id,@account account_id,@minimum minimum_quota,@target target_quota,
 w10.fn_ReplenishmentQuantity(@product,@account,@minimum,@target) recommended_quantity;
-- Missing or incompatible pairs and invalid quota parameters produce NULL.
SELECT w10.fn_ReplenishmentQuantity(-1,-1,NULL,1000) invalid_recommendation;
GO
-- adjustment writes and exact input/output assertions use transaction-local fixtures.
-- sqlcmd -S localhost\SQLEXPRESS -E -C -b -f 65001 -v DatabaseName=<new-Web-database> -i sql/week10/regression.sql
