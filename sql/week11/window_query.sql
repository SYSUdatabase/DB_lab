-- 第11周窗口查询：排名、累计值、移动平均。只读，可在任意已安装第10周扩展的库上反复执行。
-- 成交口径与第10周销售统计一致：状态为 paid、refunded、partially_refunded 的订单，
-- 金额取明细折后小计 subtotal，日期取 paid_at（已按 Asia/Shanghai 本地时间保存）。
SET NOCOUNT ON;
-- 统计区间：样例数据的成交日期在 2026-07-01 至 2026-09-30 之间，需要时直接修改这两行。
DECLARE @start_date DATE='20260701';
DECLARE @end_date DATE='20260930';

-- 1. 排名：商品按销售金额排名。RANK 并列后跳号，DENSE_RANK 并列不跳号，
--    ROW_NUMBER 给出唯一顺序；另在供应商内按销量排名，用于各供应商主推套餐的选择。
WITH sales AS (
 SELECT p.product_id,p.name,p.model_provider,
  SUM(CONVERT(BIGINT,d.quantity)) sales_quantity,
  SUM(CONVERT(DECIMAL(38,2),d.subtotal)) sales_amount,
  COUNT_BIG(DISTINCT o.order_id) order_count
 FROM dbo.Orders o JOIN dbo.OrderDetails d ON d.order_id=o.order_id
 JOIN dbo.Products p ON p.product_id=d.product_id
 WHERE o.status IN ('paid','refunded','partially_refunded')
  AND o.paid_at>=@start_date AND o.paid_at<DATEADD(DAY,1,CONVERT(DATETIME2(0),@end_date))
 GROUP BY p.product_id,p.name,p.model_provider)
SELECT product_id,name,model_provider,sales_quantity,sales_amount,order_count,
 RANK() OVER (ORDER BY sales_amount DESC) amount_rank,
 DENSE_RANK() OVER (ORDER BY sales_amount DESC) amount_dense_rank,
 ROW_NUMBER() OVER (ORDER BY sales_amount DESC,product_id) amount_row_number,
 RANK() OVER (PARTITION BY model_provider ORDER BY sales_quantity DESC) quantity_rank_in_provider
FROM sales ORDER BY amount_row_number;

-- 2. 累计值：按成交日期升序累计销售金额与销量。排序字段为 sale_date，
--    窗口为 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW（从区间第一天累加到当天）。
WITH daily AS (
 SELECT CONVERT(DATE,o.paid_at) sale_date,
  SUM(CONVERT(DECIMAL(38,2),d.subtotal)) daily_amount,
  SUM(CONVERT(BIGINT,d.quantity)) daily_quantity
 FROM dbo.Orders o JOIN dbo.OrderDetails d ON d.order_id=o.order_id
 WHERE o.status IN ('paid','refunded','partially_refunded')
  AND o.paid_at>=@start_date AND o.paid_at<DATEADD(DAY,1,CONVERT(DATETIME2(0),@end_date))
 GROUP BY CONVERT(DATE,o.paid_at))
SELECT sale_date,daily_amount,daily_quantity,
 SUM(daily_amount) OVER (ORDER BY sale_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) cumulative_amount,
 SUM(daily_quantity) OVER (ORDER BY sale_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) cumulative_quantity
FROM daily ORDER BY sale_date;

-- 3. 移动平均：最近 3 个自然日（当天及前两天）的日均销售金额和销量。
--    先用日历补齐没有成交的日期（记 0），ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
--    才等于“最近 3 天”；区间前两天不足 3 天，window_days 标出实际天数。
WITH calendar AS (
 SELECT @start_date sale_date
 UNION ALL SELECT DATEADD(DAY,1,sale_date) FROM calendar WHERE sale_date<@end_date),
daily AS (
 SELECT CONVERT(DATE,o.paid_at) sale_date,
  SUM(CONVERT(DECIMAL(38,2),d.subtotal)) daily_amount,
  SUM(CONVERT(BIGINT,d.quantity)) daily_quantity
 FROM dbo.Orders o JOIN dbo.OrderDetails d ON d.order_id=o.order_id
 WHERE o.status IN ('paid','refunded','partially_refunded')
  AND o.paid_at>=@start_date AND o.paid_at<DATEADD(DAY,1,CONVERT(DATETIME2(0),@end_date))
 GROUP BY CONVERT(DATE,o.paid_at))
SELECT c.sale_date,COALESCE(d.daily_amount,0) daily_amount,COALESCE(d.daily_quantity,0) daily_quantity,
 COUNT(*) OVER (ORDER BY c.sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) window_days,
 CONVERT(DECIMAL(38,2),AVG(COALESCE(d.daily_amount,0)) OVER (ORDER BY c.sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)) moving_avg_amount_3d,
 CONVERT(DECIMAL(38,2),AVG(CONVERT(DECIMAL(38,2),COALESCE(d.daily_quantity,0))) OVER (ORDER BY c.sale_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)) moving_avg_quantity_3d
FROM calendar c LEFT JOIN daily d ON d.sale_date=c.sale_date
ORDER BY c.sale_date OPTION (MAXRECURSION 3660);
