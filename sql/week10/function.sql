SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE FUNCTION w10.fn_OrderDiscount(@gross_amount DECIMAL(18,2))
RETURNS TABLE AS RETURN (
 SELECT discount_rate,CONVERT(DECIMAL(18,2),ROUND(@gross_amount*discount_rate,2)) discount_amount
 FROM (SELECT CONVERT(DECIMAL(5,4),CASE WHEN @gross_amount>=500 THEN 0.10 WHEN @gross_amount>=100 THEN 0.05 ELSE 0 END) discount_rate) r
 WHERE @gross_amount>=0
);
GO
CREATE FUNCTION w10.fn_ReplenishmentQuantity(@product_id INT,@account_id INT,@minimum_quota BIGINT,@target_quota BIGINT)
RETURNS BIGINT AS
BEGIN
 DECLARE @current BIGINT,@minimum BIGINT;
 SELECT @current=i.current_quota,@minimum=COALESCE(@minimum_quota,a.safety_threshold)
 FROM dbo.Products p JOIN dbo.UpstreamAccount a ON p.model_provider=a.provider
 JOIN dbo.Inventory i ON i.account_id=a.account_id
 WHERE p.product_id=@product_id AND a.account_id=@account_id
 AND a.status='active' AND a.created_at<=CONVERT(DATETIME2(0),SYSDATETIME())
 AND (a.expires_at IS NULL OR a.expires_at>CONVERT(DATETIME2(0),SYSDATETIME()))
 AND i.current_quota=a.total_quota-a.used_quota;
 IF @current IS NULL OR @minimum IS NULL OR @minimum<0 OR @target_quota IS NULL OR @target_quota<@minimum RETURN NULL;
 RETURN CASE WHEN @current<@minimum AND @target_quota>@current THEN @target_quota-@current ELSE 0 END;
END;
GO
CREATE FUNCTION w10.fn_SalesSummary(@start_date DATE,@end_date DATE)
RETURNS TABLE AS RETURN (
 SELECT p.product_id,p.name name,SUM(CONVERT(BIGINT,d.quantity)) sales_quantity,
 SUM(CONVERT(DECIMAL(38,2),d.subtotal)) sales_amount,COUNT_BIG(DISTINCT o.order_id) order_count
 FROM dbo.Orders o JOIN dbo.OrderDetails d ON d.order_id=o.order_id
 JOIN dbo.Products p ON p.product_id=d.product_id
 WHERE @start_date<=@end_date AND o.status IN('paid','refunded','partially_refunded')
 AND o.paid_at>=CONVERT(DATETIME2(0),@start_date)
 AND (@end_date='99991231' OR o.paid_at<DATEADD(DAY,1,CONVERT(DATETIME2(0),NULLIF(@end_date,CONVERT(DATE,'99991231')))))
 GROUP BY p.product_id,p.name
);
GO
