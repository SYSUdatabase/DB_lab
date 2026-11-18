-- Optional stage-2 demonstration dashboard extension.
-- Read-only analytics, accessible only to active staff and administrator sessions.
-- Run with sqlcmd -b -d TokenHubDB_v11_Web... -i sql/app/dashboard.sql
SET NOCOUNT ON;
IF DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]Web%'
    THROW 55801, 'Dashboard extension requires a v11 Web database', 1;
IF OBJECT_ID(N'app.[Execute]', N'P') IS NULL OR DATABASE_PRINCIPAL_ID(N'app_runtime') IS NULL
    THROW 55802, 'Install the stage-2 Web application first', 1;
GO
CREATE OR ALTER PROCEDURE app.Dashboard
    @token_hash VARBINARY(32)
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    IF @token_hash IS NULL OR DATALENGTH(@token_hash) <> 32
        THROW 55001, 'Authentication required', 1;

    DECLARE @role VARCHAR(50);
    SELECT @role = r.role_name
    FROM app.Sessions AS s
    JOIN dbo.Employees AS e ON e.employee_id = s.employee_id AND e.status = 'active'
    JOIN dbo.Roles AS r ON r.role_id = e.role_id AND r.role_name IN ('staff', 'admin')
    WHERE s.token_hash = @token_hash AND s.revoked_at IS NULL
      AND s.expires_at > SYSDATETIME();

    IF @role IS NULL
        THROW 55003, 'Employee role required', 1;

    DECLARE @now DATETIME2(0) = SYSDATETIME();
    DECLARE @today DATE = CONVERT(DATE, @now);
    DECLARE @data NVARCHAR(MAX);

    SET @data = (
        SELECT
            JSON_QUERY((
                SELECT
                    COUNT_BIG(*) AS total_orders,
                    COALESCE(SUM(CASE WHEN o.status = 'pending' THEN CONVERT(BIGINT, 1) ELSE 0 END), 0) AS pending_orders,
                    COALESCE(SUM(CASE WHEN o.status = 'paid' THEN CONVERT(BIGINT, 1) ELSE 0 END), 0) AS paid_orders,
                    COALESCE(SUM(CASE WHEN o.status IN ('paid', 'refunded', 'partially_refunded')
                        THEN CONVERT(DECIMAL(22,2), o.total_amount) ELSE CONVERT(DECIMAL(22,2), 0) END), 0) AS gross_paid_amount,
                    (SELECT COALESCE(SUM(CONVERT(DECIMAL(22,2), refund_amount)), 0)
                     FROM dbo.RefundLedger) AS refund_amount,
                    (SELECT COUNT_BIG(*) FROM dbo.Products WHERE status = 'active') AS active_products,
                    (SELECT COUNT_BIG(*) FROM dbo.UpstreamAccount a
                     JOIN dbo.Inventory i ON i.account_id = a.account_id
                     WHERE a.status = 'active' AND i.current_quota < a.safety_threshold) AS low_stock_accounts
                FROM dbo.Orders o
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )) AS metrics,
            JSON_QUERY((
                SELECT status, COUNT_BIG(*) AS order_count
                FROM dbo.Orders GROUP BY status
                ORDER BY CASE status WHEN 'pending' THEN 1 WHEN 'paid' THEN 2
                  WHEN 'partially_refunded' THEN 3 WHEN 'refunded' THEN 4
                  WHEN 'cancelled' THEN 5 ELSE 6 END
                FOR JSON PATH
            )) AS statuses,
            JSON_QUERY((
                SELECT CONVERT(CHAR(10), DATEADD(DAY, n.day_offset - 13, @today), 23) AS [day],
                       (SELECT COUNT_BIG(*) FROM dbo.Orders o
                        WHERE o.created_at >= DATEADD(DAY, n.day_offset - 13, @today)
                          AND o.created_at < DATEADD(DAY, n.day_offset - 12, @today)) AS order_count
                FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11),(12),(13)) AS n(day_offset)
                ORDER BY n.day_offset FOR JSON PATH
            )) AS daily_orders,
            JSON_QUERY((
                SELECT TOP (5) a.account_id, a.account_name, a.provider,
                       i.current_quota, a.safety_threshold
                FROM dbo.UpstreamAccount a JOIN dbo.Inventory i ON i.account_id = a.account_id
                WHERE a.status = 'active' AND i.current_quota < a.safety_threshold
                ORDER BY i.current_quota ASC, a.account_id ASC FOR JSON PATH
            )) AS low_stock,
            CONVERT(VARCHAR(19), @now, 120) AS refreshed_at
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );
    SELECT @data AS data;
END;
GO
GRANT EXECUTE ON app.Dashboard TO app_runtime;
GO
