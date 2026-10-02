/*
第三周数据库实验：14 张业务表 DDL（注释版）。
目标：把第二周数据字典落实为字段、主键、候选码、外键、默认值和 CHECK 约束，并按依赖顺序建表。
*/

-- Week 3 / 01_create_tables.sql
-- 14 tables translated from week2_deliverables_v2.md.
-- Potentially Chinese free-text columns use NVARCHAR; timestamps use DATETIME2(0).

USE [TokenHubDB_Week3];  -- 作用：切换数据库上下文，后续语句都在这个数据库中执行
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO
SET ANSI_NULLS ON;  -- 作用：启用 SQL Server 标准 NULL 比较行为
SET QUOTED_IDENTIFIER ON;  -- 作用：启用标准引号标识符行为
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.Roles (  -- 作用：创建 Roles 表，开始定义字段和完整性约束
    role_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Roles PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    role_name VARCHAR(50) NOT NULL CONSTRAINT UQ_Roles_role_name UNIQUE,  -- 作用：限制当前字段或字段组合不可重复
    description NVARCHAR(255) NULL,
    permissions NVARCHAR(MAX) NULL,
    CONSTRAINT CK_Roles_role_name CHECK (role_name IN ('admin','staff','customer')),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_Roles_permissions_json CHECK (permissions IS NULL OR ISJSON(permissions) = 1)  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.Users (  -- 作用：创建 Users 表，开始定义字段和完整性约束
    user_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Users PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    username VARCHAR(50) NOT NULL CONSTRAINT UQ_Users_username UNIQUE,  -- 作用：限制当前字段或字段组合不可重复
    password_hash VARCHAR(60) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    email VARCHAR(100) NOT NULL CONSTRAINT UQ_Users_email UNIQUE,  -- 作用：限制当前字段或字段组合不可重复
    phone VARCHAR(20) NULL,
    status VARCHAR(20) NOT NULL CONSTRAINT DF_Users_status DEFAULT ('active'),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_Users_created_at DEFAULT (SYSDATETIME()),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    updated_at DATETIME2(0) NOT NULL CONSTRAINT DF_Users_updated_at DEFAULT (SYSDATETIME()),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    CONSTRAINT CK_Users_username_len CHECK (LEN(username) BETWEEN 3 AND 50),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_Users_status CHECK (status IN ('active','frozen','deleted'))  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.Products (  -- 作用：创建 Products 表，开始定义字段和完整性约束
    product_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Products PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    name NVARCHAR(100) NOT NULL CONSTRAINT UQ_Products_name UNIQUE,  -- 作用：限制当前字段或字段组合不可重复
    description NVARCHAR(MAX) NULL,
    price DECIMAL(10,2) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    model_provider VARCHAR(50) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    token_amount INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    required_upstream_tokens INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    status VARCHAR(20) NOT NULL CONSTRAINT DF_Products_status DEFAULT ('active'),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_Products_created_at DEFAULT (SYSDATETIME()),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    CONSTRAINT UQ_Products_provider_tokens UNIQUE (model_provider, token_amount),  -- 作用：定义唯一约束，阻止业务候选码重复
    CONSTRAINT CK_Products_price CHECK (price > 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_Products_provider CHECK (model_provider IN ('OpenAI','Claude','Gemini','Other')),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_Products_token_amount CHECK (token_amount > 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_Products_upstream_tokens CHECK (required_upstream_tokens > 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_Products_status CHECK (status IN ('active','inactive','discontinued'))  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.UpstreamAccount (  -- 作用：创建 UpstreamAccount 表，开始定义字段和完整性约束
    account_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_UpstreamAccount PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    provider VARCHAR(50) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    account_name NVARCHAR(100) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    api_key NVARCHAR(255) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    total_quota BIGINT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    used_quota BIGINT NOT NULL CONSTRAINT DF_UpstreamAccount_used DEFAULT (0),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    safety_threshold BIGINT NOT NULL CONSTRAINT DF_UpstreamAccount_threshold DEFAULT (1000),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    status VARCHAR(20) NOT NULL CONSTRAINT DF_UpstreamAccount_status DEFAULT ('active'),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    expires_at DATETIME2(0) NULL,
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_UpstreamAccount_created DEFAULT (SYSDATETIME()),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    updated_at DATETIME2(0) NOT NULL CONSTRAINT DF_UpstreamAccount_updated DEFAULT (SYSDATETIME()),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    CONSTRAINT UQ_UpstreamAccount_provider_name UNIQUE (provider, account_name),  -- 作用：定义唯一约束，阻止业务候选码重复
    CONSTRAINT CK_UpstreamAccount_provider CHECK (provider IN ('OpenAI','Claude','Gemini','Other')),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_UpstreamAccount_total CHECK (total_quota > 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_UpstreamAccount_used CHECK (used_quota >= 0 AND used_quota <= total_quota),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_UpstreamAccount_threshold CHECK (safety_threshold >= 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_UpstreamAccount_status CHECK (status IN ('active','suspended','depleted','expired'))  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.Inventory (  -- 作用：创建 Inventory 表，开始定义字段和完整性约束
    inventory_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Inventory PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    account_id INT NOT NULL CONSTRAINT UQ_Inventory_account UNIQUE,  -- 作用：限制当前字段或字段组合不可重复
    current_quota BIGINT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    last_updated_at DATETIME2(0) NOT NULL CONSTRAINT DF_Inventory_updated DEFAULT (SYSDATETIME()),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    CONSTRAINT FK_Inventory_UpstreamAccount FOREIGN KEY (account_id)  -- 作用：定义外键约束，保证引用值必须来自对应主表
        REFERENCES dbo.UpstreamAccount(account_id),
    CONSTRAINT CK_Inventory_current_quota CHECK (current_quota >= 0)  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.Employees (  -- 作用：创建 Employees 表，开始定义字段和完整性约束
    employee_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Employees PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    name NVARCHAR(50) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    role_id INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    account VARCHAR(50) NOT NULL CONSTRAINT UQ_Employees_account UNIQUE,  -- 作用：限制当前字段或字段组合不可重复
    password_hash VARCHAR(60) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    hire_date DATE NOT NULL CONSTRAINT DF_Employees_hire_date DEFAULT (CONVERT(date, SYSDATETIME())),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    status VARCHAR(20) NOT NULL CONSTRAINT DF_Employees_status DEFAULT ('active'),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    CONSTRAINT FK_Employees_Roles FOREIGN KEY (role_id) REFERENCES dbo.Roles(role_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT CK_Employees_status CHECK (status IN ('active','inactive'))  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.Orders (  -- 作用：创建 Orders 表，开始定义字段和完整性约束
    order_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Orders PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    user_id INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    total_amount DECIMAL(10,2) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    total_tokens BIGINT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    status VARCHAR(20) NOT NULL CONSTRAINT DF_Orders_status DEFAULT ('pending'),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_Orders_created DEFAULT (SYSDATETIME()),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    paid_at DATETIME2(0) NULL,
    CONSTRAINT FK_Orders_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(user_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT CK_Orders_amount CHECK (total_amount >= 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_Orders_tokens CHECK (total_tokens >= 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_Orders_status CHECK (status IN ('pending','paid','cancelled','refunded'))  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.OrderDetails (  -- 作用：创建 OrderDetails 表，开始定义字段和完整性约束
    detail_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrderDetails PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    order_id INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    product_id INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    quantity INT NOT NULL CONSTRAINT DF_OrderDetails_quantity DEFAULT (1),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    unit_price DECIMAL(10,2) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    subtotal DECIMAL(10,2) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    tokens_per_unit INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    total_tokens BIGINT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    CONSTRAINT UQ_OrderDetails_order_product UNIQUE (order_id, product_id),  -- 作用：定义唯一约束，阻止业务候选码重复
    CONSTRAINT FK_OrderDetails_Orders FOREIGN KEY (order_id) REFERENCES dbo.Orders(order_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT FK_OrderDetails_Products FOREIGN KEY (product_id) REFERENCES dbo.Products(product_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT CK_OrderDetails_quantity CHECK (quantity > 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_OrderDetails_unit_price CHECK (unit_price > 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_OrderDetails_subtotal CHECK (subtotal >= 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_OrderDetails_tokens_per_unit CHECK (tokens_per_unit > 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_OrderDetails_total_tokens CHECK (total_tokens >= 0)  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.InventoryLog (  -- 作用：创建 InventoryLog 表，开始定义字段和完整性约束
    log_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_InventoryLog PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    account_id INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    change_type VARCHAR(20) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    change_amount BIGINT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    reference_id INT NULL,
    reference_type VARCHAR(20) NULL,
    reason NVARCHAR(255) NULL,
    operator_id INT NULL,
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_InventoryLog_created DEFAULT (SYSDATETIME()),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    CONSTRAINT FK_InventoryLog_Account FOREIGN KEY (account_id) REFERENCES dbo.UpstreamAccount(account_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT FK_InventoryLog_Operator FOREIGN KEY (operator_id) REFERENCES dbo.Employees(employee_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT CK_InventoryLog_type CHECK (change_type IN ('purchase','consumption','restock','adjustment')),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_InventoryLog_amount CHECK (change_amount <> 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_InventoryLog_reference_type CHECK (reference_type IS NULL OR reference_type IN ('order','restock_task','manual'))  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.TokenBalances (  -- 作用：创建 TokenBalances 表，开始定义字段和完整性约束
    balance_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TokenBalances PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    user_id INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    model_provider VARCHAR(50) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    remaining_tokens BIGINT NOT NULL CONSTRAINT DF_TokenBalances_remaining DEFAULT (0),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    updated_at DATETIME2(0) NOT NULL CONSTRAINT DF_TokenBalances_updated DEFAULT (SYSDATETIME()),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    CONSTRAINT UQ_TokenBalances_user_provider UNIQUE (user_id, model_provider),  -- 作用：定义唯一约束，阻止业务候选码重复
    CONSTRAINT FK_TokenBalances_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(user_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT CK_TokenBalances_provider CHECK (model_provider IN ('OpenAI','Claude','Gemini','Other')),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_TokenBalances_remaining CHECK (remaining_tokens >= 0)  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.TokenUsageLogs (  -- 作用：创建 TokenUsageLogs 表，开始定义字段和完整性约束
    log_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TokenUsageLogs PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    user_id INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    product_id INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    account_id INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    tokens_used INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    upstream_tokens_consumed INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    api_endpoint VARCHAR(255) NULL,
    used_at DATETIME2(0) NOT NULL CONSTRAINT DF_TokenUsageLogs_used DEFAULT (SYSDATETIME()),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    CONSTRAINT FK_TokenUsageLogs_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(user_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT FK_TokenUsageLogs_Products FOREIGN KEY (product_id) REFERENCES dbo.Products(product_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT FK_TokenUsageLogs_Account FOREIGN KEY (account_id) REFERENCES dbo.UpstreamAccount(account_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT CK_TokenUsageLogs_tokens CHECK (tokens_used > 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_TokenUsageLogs_upstream CHECK (upstream_tokens_consumed > 0)  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.UsageSummary (  -- 作用：创建 UsageSummary 表，开始定义字段和完整性约束
    summary_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_UsageSummary PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    user_id INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    product_id INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    period_type VARCHAR(10) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    period_start DATE NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    period_end DATE NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    total_tokens_used BIGINT NOT NULL CONSTRAINT DF_UsageSummary_tokens DEFAULT (0),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    total_upstream_consumed BIGINT NOT NULL CONSTRAINT DF_UsageSummary_upstream DEFAULT (0),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    request_count INT NOT NULL CONSTRAINT DF_UsageSummary_requests DEFAULT (0),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    last_updated_at DATETIME2(0) NOT NULL CONSTRAINT DF_UsageSummary_updated DEFAULT (SYSDATETIME()),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    CONSTRAINT UQ_UsageSummary_key UNIQUE (user_id, product_id, period_type, period_start),  -- 作用：定义唯一约束，阻止业务候选码重复
    CONSTRAINT FK_UsageSummary_Users FOREIGN KEY (user_id) REFERENCES dbo.Users(user_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT FK_UsageSummary_Products FOREIGN KEY (product_id) REFERENCES dbo.Products(product_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT CK_UsageSummary_period_type CHECK (period_type IN ('daily','weekly','monthly')),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_UsageSummary_dates CHECK (period_end >= period_start),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_UsageSummary_tokens CHECK (total_tokens_used >= 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_UsageSummary_upstream CHECK (total_upstream_consumed >= 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_UsageSummary_requests CHECK (request_count >= 0)  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.RestockTask (  -- 作用：创建 RestockTask 表，开始定义字段和完整性约束
    task_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RestockTask PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    account_id INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    trigger_reason VARCHAR(50) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    restock_method VARCHAR(50) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    target_amount BIGINT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    actual_amount BIGINT NULL,
    created_by INT NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    assigned_to INT NULL,
    status VARCHAR(20) NOT NULL CONSTRAINT DF_RestockTask_status DEFAULT ('pending'),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_RestockTask_created DEFAULT (SYSDATETIME()),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    completed_at DATETIME2(0) NULL,
    notes NVARCHAR(MAX) NULL,
    CONSTRAINT FK_RestockTask_Account FOREIGN KEY (account_id) REFERENCES dbo.UpstreamAccount(account_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT FK_RestockTask_CreatedBy FOREIGN KEY (created_by) REFERENCES dbo.Employees(employee_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT FK_RestockTask_AssignedTo FOREIGN KEY (assigned_to) REFERENCES dbo.Employees(employee_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT CK_RestockTask_trigger CHECK (trigger_reason IN ('low_quota','scheduled','manual')),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_RestockTask_method CHECK (restock_method IN ('api_recharge','manual_purchase')),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_RestockTask_target CHECK (target_amount > 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_RestockTask_actual CHECK (actual_amount IS NULL OR actual_amount >= 0),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_RestockTask_status CHECK (status IN ('pending','in_progress','completed','failed'))  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

CREATE TABLE dbo.ExceptionLog (  -- 作用：创建 ExceptionLog 表，开始定义字段和完整性约束
    exception_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ExceptionLog PRIMARY KEY,  -- 作用：把当前字段设为主键，作为记录的唯一标识
    exception_type VARCHAR(50) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    related_table VARCHAR(50) NULL,
    related_id INT NULL,
    error_message NVARCHAR(MAX) NOT NULL,  -- 作用：要求当前字段必须有值，避免关键业务信息缺失
    error_detail NVARCHAR(MAX) NULL,
    occurred_at DATETIME2(0) NOT NULL CONSTRAINT DF_ExceptionLog_occurred DEFAULT (SYSDATETIME()),  -- 作用：为当前字段设置默认值，省略字段时自动补齐
    handled_by INT NULL,
    handle_result VARCHAR(50) NULL,
    handle_notes NVARCHAR(MAX) NULL,
    handled_at DATETIME2(0) NULL,
    CONSTRAINT FK_ExceptionLog_HandledBy FOREIGN KEY (handled_by) REFERENCES dbo.Employees(employee_id),  -- 作用：定义外键约束，保证引用值必须来自对应主表
    CONSTRAINT CK_ExceptionLog_type CHECK (exception_type IN ('api_error','payment_error','inventory_error','system_error')),  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
    CONSTRAINT CK_ExceptionLog_result CHECK (handle_result IS NULL OR handle_result IN ('resolved','ignored','escalated'))  -- 作用：定义 CHECK 约束，把状态或数值限制在合法业务域
);
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO
