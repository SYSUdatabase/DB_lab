-- Week 3 / 01_create_tables.sql
-- 14 tables translated from week2_deliverables_v2.md.
-- Potentially Chinese free-text columns use NVARCHAR; timestamps use DATETIME2(0).

USE [TokenHubDB_Week3];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE dbo.Roles (
    role_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Roles PRIMARY KEY,
    role_name VARCHAR(50) NOT NULL CONSTRAINT UQ_Roles_role_name UNIQUE,
    description NVARCHAR(255) NULL,
    permissions NVARCHAR(MAX) NULL,
    CONSTRAINT CK_Roles_role_name CHECK (role_name IN ('admin','staff','customer')),
    CONSTRAINT CK_Roles_permissions_json CHECK (permissions IS NULL OR ISJSON(permissions) = 1)
);
GO

CREATE TABLE dbo.Users (
    user_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Users PRIMARY KEY,
    username VARCHAR(50) NOT NULL CONSTRAINT UQ_Users_username UNIQUE,
    password_hash VARCHAR(60) NOT NULL,
    email VARCHAR(100) NOT NULL CONSTRAINT UQ_Users_email UNIQUE,
    phone VARCHAR(20) NULL,
    status VARCHAR(20) NOT NULL CONSTRAINT DF_Users_status DEFAULT ('active'),
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_Users_created_at DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(0) NOT NULL CONSTRAINT DF_Users_updated_at DEFAULT (SYSDATETIME()),
    CONSTRAINT CK_Users_username_len CHECK (LEN(username) BETWEEN 3 AND 50),
    CONSTRAINT CK_Users_status CHECK (status IN ('active','frozen','deleted'))
);
GO

CREATE TABLE dbo.Products (
    product_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Products PRIMARY KEY,
    name NVARCHAR(100) NOT NULL CONSTRAINT UQ_Products_name UNIQUE,
    description NVARCHAR(MAX) NULL,
    price DECIMAL(10,2) NOT NULL,
    model_provider VARCHAR(50) NOT NULL,
    token_amount INT NOT NULL,
    required_upstream_tokens INT NOT NULL,
    status VARCHAR(20) NOT NULL CONSTRAINT DF_Products_status DEFAULT ('active'),
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_Products_created_at DEFAULT (SYSDATETIME()),
    CONSTRAINT UQ_Products_provider_tokens UNIQUE (model_provider, token_amount),
    CONSTRAINT CK_Products_price CHECK (price > 0),
    CONSTRAINT CK_Products_provider CHECK (model_provider IN ('OpenAI','Claude','Gemini','Other')),
    CONSTRAINT CK_Products_token_amount CHECK (token_amount > 0),
    CONSTRAINT CK_Products_upstream_tokens CHECK (required_upstream_tokens > 0),
    CONSTRAINT CK_Products_status CHECK (status IN ('active','inactive','discontinued'))
);
GO

CREATE TABLE dbo.UpstreamAccount (
    account_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_UpstreamAccount PRIMARY KEY,
    provider VARCHAR(50) NOT NULL,
    account_name NVARCHAR(100) NOT NULL,
    api_key NVARCHAR(255) NOT NULL,
    total_quota BIGINT NOT NULL,
    used_quota BIGINT NOT NULL CONSTRAINT DF_UpstreamAccount_used DEFAULT (0),
    safety_threshold BIGINT NOT NULL CONSTRAINT DF_UpstreamAccount_threshold DEFAULT (1000),
    status VARCHAR(20) NOT NULL CONSTRAINT DF_UpstreamAccount_status DEFAULT ('active'),
    expires_at DATETIME2(0) NULL,
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_UpstreamAccount_created DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(0) NOT NULL CONSTRAINT DF_UpstreamAccount_updated DEFAULT (SYSDATETIME()),
    CONSTRAINT UQ_UpstreamAccount_provider_name UNIQUE (provider, account_name),
    CONSTRAINT CK_UpstreamAccount_provider CHECK (provider IN ('OpenAI','Claude','Gemini','Other')),
    CONSTRAINT CK_UpstreamAccount_total CHECK (total_quota > 0),
    CONSTRAINT CK_UpstreamAccount_used CHECK (used_quota >= 0 AND used_quota <= total_quota),
    CONSTRAINT CK_UpstreamAccount_threshold CHECK (safety_threshold >= 0),
    CONSTRAINT CK_UpstreamAccount_status CHECK (status IN ('active','suspended','depleted','expired'))
);
GO

CREATE TABLE dbo.Inventory (
    inventory_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Inventory PRIMARY KEY,
    account_id INT NOT NULL CONSTRAINT UQ_Inventory_account UNIQUE,
    current_quota BIGINT NOT NULL,
    last_updated_at DATETIME2(0) NOT NULL CONSTRAINT DF_Inventory_updated DEFAULT (SYSDATETIME()),
    CONSTRAINT FK_Inventory_UpstreamAccount FOREIGN KEY (account_id)
        REFERENCES dbo.UpstreamAccount(account_id),
    CONSTRAINT CK_Inventory_current_quota CHECK (current_quota >= 0)
);
GO

CREATE TABLE dbo.Employees (
    employee_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Employees PRIMARY KEY,
    name NVARCHAR(50) NOT NULL,
    role_id INT NOT NULL,
    account VARCHAR(50) NOT NULL CONSTRAINT UQ_Employees_account UNIQUE,
    password_hash VARCHAR(60) NOT NULL,
    hire_date DATE NOT NULL CONSTRAINT DF_Employees_hire_date DEFAULT (CONVERT(date, SYSDATETIME())),
    status VARCHAR(20) NOT NULL CONSTRAINT DF_Employees_status DEFAULT ('active'),
    CONSTRAINT FK_Employees_Roles FOREIGN KEY (role_id) REFERENCES dbo.Roles(role_id),
    CONSTRAINT CK_Employees_status CHECK (status IN ('active','inactive'))
);
GO

CREATE TABLE dbo.Orders (
    order_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Orders PRIMARY KEY,
    user_id INT NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    total_tokens BIGINT NOT NULL,
    status VARCHAR(20) NOT NULL CONSTRAINT DF_Orders_status DEFAULT ('pending'),
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_Orders_created DEFAULT (SYSDATETIME()),
    paid_at DATETIME2(0) NULL,
    CONSTRAINT FK_Orders_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(user_id),
    CONSTRAINT CK_Orders_amount CHECK (total_amount >= 0),
    CONSTRAINT CK_Orders_tokens CHECK (total_tokens >= 0),
    CONSTRAINT CK_Orders_status CHECK (status IN ('pending','paid','cancelled','refunded'))
);
GO

CREATE TABLE dbo.OrderDetails (
    detail_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrderDetails PRIMARY KEY,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL CONSTRAINT DF_OrderDetails_quantity DEFAULT (1),
    unit_price DECIMAL(10,2) NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,
    tokens_per_unit INT NOT NULL,
    total_tokens BIGINT NOT NULL,
    CONSTRAINT UQ_OrderDetails_order_product UNIQUE (order_id, product_id),
    CONSTRAINT FK_OrderDetails_Orders FOREIGN KEY (order_id) REFERENCES dbo.Orders(order_id),
    CONSTRAINT FK_OrderDetails_Products FOREIGN KEY (product_id) REFERENCES dbo.Products(product_id),
    CONSTRAINT CK_OrderDetails_quantity CHECK (quantity > 0),
    CONSTRAINT CK_OrderDetails_unit_price CHECK (unit_price > 0),
    CONSTRAINT CK_OrderDetails_subtotal CHECK (subtotal >= 0),
    CONSTRAINT CK_OrderDetails_tokens_per_unit CHECK (tokens_per_unit > 0),
    CONSTRAINT CK_OrderDetails_total_tokens CHECK (total_tokens >= 0)
);
GO

CREATE TABLE dbo.InventoryLog (
    log_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InventoryLog PRIMARY KEY,
    account_id INT NOT NULL,
    change_type VARCHAR(20) NOT NULL,
    change_amount BIGINT NOT NULL,
    reference_id INT NULL,
    reference_type VARCHAR(20) NULL,
    reason NVARCHAR(255) NULL,
    operator_id INT NULL,
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_InventoryLog_created DEFAULT (SYSDATETIME()),
    CONSTRAINT FK_InventoryLog_Account FOREIGN KEY (account_id) REFERENCES dbo.UpstreamAccount(account_id),
    CONSTRAINT FK_InventoryLog_Operator FOREIGN KEY (operator_id) REFERENCES dbo.Employees(employee_id),
    CONSTRAINT CK_InventoryLog_type CHECK (change_type IN ('purchase','consumption','restock','adjustment')),
    CONSTRAINT CK_InventoryLog_amount CHECK (change_amount <> 0),
    CONSTRAINT CK_InventoryLog_reference_type CHECK (reference_type IS NULL OR reference_type IN ('order','restock_task','manual'))
);
GO

CREATE TABLE dbo.TokenBalances (
    balance_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TokenBalances PRIMARY KEY,
    user_id INT NOT NULL,
    model_provider VARCHAR(50) NOT NULL,
    remaining_tokens BIGINT NOT NULL CONSTRAINT DF_TokenBalances_remaining DEFAULT (0),
    updated_at DATETIME2(0) NOT NULL CONSTRAINT DF_TokenBalances_updated DEFAULT (SYSDATETIME()),
    CONSTRAINT UQ_TokenBalances_user_provider UNIQUE (user_id, model_provider),
    CONSTRAINT FK_TokenBalances_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(user_id),
    CONSTRAINT CK_TokenBalances_provider CHECK (model_provider IN ('OpenAI','Claude','Gemini','Other')),
    CONSTRAINT CK_TokenBalances_remaining CHECK (remaining_tokens >= 0)
);
GO

CREATE TABLE dbo.TokenUsageLogs (
    log_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TokenUsageLogs PRIMARY KEY,
    user_id INT NOT NULL,
    product_id INT NOT NULL,
    account_id INT NOT NULL,
    tokens_used INT NOT NULL,
    upstream_tokens_consumed INT NOT NULL,
    api_endpoint VARCHAR(255) NULL,
    used_at DATETIME2(0) NOT NULL CONSTRAINT DF_TokenUsageLogs_used DEFAULT (SYSDATETIME()),
    CONSTRAINT FK_TokenUsageLogs_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(user_id),
    CONSTRAINT FK_TokenUsageLogs_Products FOREIGN KEY (product_id) REFERENCES dbo.Products(product_id),
    CONSTRAINT FK_TokenUsageLogs_Account FOREIGN KEY (account_id) REFERENCES dbo.UpstreamAccount(account_id),
    CONSTRAINT CK_TokenUsageLogs_tokens CHECK (tokens_used > 0),
    CONSTRAINT CK_TokenUsageLogs_upstream CHECK (upstream_tokens_consumed > 0)
);
GO

CREATE TABLE dbo.UsageSummary (
    summary_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_UsageSummary PRIMARY KEY,
    user_id INT NOT NULL,
    product_id INT NOT NULL,
    period_type VARCHAR(10) NOT NULL,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    total_tokens_used BIGINT NOT NULL CONSTRAINT DF_UsageSummary_tokens DEFAULT (0),
    total_upstream_consumed BIGINT NOT NULL CONSTRAINT DF_UsageSummary_upstream DEFAULT (0),
    request_count INT NOT NULL CONSTRAINT DF_UsageSummary_requests DEFAULT (0),
    last_updated_at DATETIME2(0) NOT NULL CONSTRAINT DF_UsageSummary_updated DEFAULT (SYSDATETIME()),
    CONSTRAINT UQ_UsageSummary_key UNIQUE (user_id, product_id, period_type, period_start),
    CONSTRAINT FK_UsageSummary_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(user_id),
    CONSTRAINT FK_UsageSummary_Products FOREIGN KEY (product_id) REFERENCES dbo.Products(product_id),
    CONSTRAINT CK_UsageSummary_period_type CHECK (period_type IN ('daily','weekly','monthly')),
    CONSTRAINT CK_UsageSummary_dates CHECK (period_end >= period_start),
    CONSTRAINT CK_UsageSummary_tokens CHECK (total_tokens_used >= 0),
    CONSTRAINT CK_UsageSummary_upstream CHECK (total_upstream_consumed >= 0),
    CONSTRAINT CK_UsageSummary_requests CHECK (request_count >= 0)
);
GO

CREATE TABLE dbo.RestockTask (
    task_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RestockTask PRIMARY KEY,
    account_id INT NOT NULL,
    trigger_reason VARCHAR(50) NOT NULL,
    restock_method VARCHAR(50) NOT NULL,
    target_amount BIGINT NOT NULL,
    actual_amount BIGINT NULL,
    created_by INT NOT NULL,
    assigned_to INT NULL,
    status VARCHAR(20) NOT NULL CONSTRAINT DF_RestockTask_status DEFAULT ('pending'),
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_RestockTask_created DEFAULT (SYSDATETIME()),
    completed_at DATETIME2(0) NULL,
    notes NVARCHAR(MAX) NULL,
    CONSTRAINT FK_RestockTask_Account FOREIGN KEY (account_id) REFERENCES dbo.UpstreamAccount(account_id),
    CONSTRAINT FK_RestockTask_CreatedBy FOREIGN KEY (created_by) REFERENCES dbo.Employees(employee_id),
    CONSTRAINT FK_RestockTask_AssignedTo FOREIGN KEY (assigned_to) REFERENCES dbo.Employees(employee_id),
    CONSTRAINT CK_RestockTask_trigger CHECK (trigger_reason IN ('low_quota','scheduled','manual')),
    CONSTRAINT CK_RestockTask_method CHECK (restock_method IN ('api_recharge','manual_purchase')),
    CONSTRAINT CK_RestockTask_target CHECK (target_amount > 0),
    CONSTRAINT CK_RestockTask_actual CHECK (actual_amount IS NULL OR actual_amount >= 0),
    CONSTRAINT CK_RestockTask_status CHECK (status IN ('pending','in_progress','completed','failed'))
);
GO

CREATE TABLE dbo.ExceptionLog (
    exception_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ExceptionLog PRIMARY KEY,
    exception_type VARCHAR(50) NOT NULL,
    related_table VARCHAR(50) NULL,
    related_id INT NULL,
    error_message NVARCHAR(MAX) NOT NULL,
    error_detail NVARCHAR(MAX) NULL,
    occurred_at DATETIME2(0) NOT NULL CONSTRAINT DF_ExceptionLog_occurred DEFAULT (SYSDATETIME()),
    handled_by INT NULL,
    handle_result VARCHAR(50) NULL,
    handle_notes NVARCHAR(MAX) NULL,
    handled_at DATETIME2(0) NULL,
    CONSTRAINT FK_ExceptionLog_HandledBy FOREIGN KEY (handled_by) REFERENCES dbo.Employees(employee_id),
    CONSTRAINT CK_ExceptionLog_type CHECK (exception_type IN ('api_error','payment_error','inventory_error','system_error')),
    CONSTRAINT CK_ExceptionLog_result CHECK (handle_result IS NULL OR handle_result IN ('resolved','ignored','escalated'))
);
GO
