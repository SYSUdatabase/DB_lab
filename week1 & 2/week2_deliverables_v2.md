# 第二周任务交付物 v2

## 1. 表清单

### 1.1 用户表（Users）
**实体说明**：存储注册用户信息，包括个人资料和账户状态。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| user_id | INT | - | NOT NULL | - | 自增正整数 | 用户唯一标识 |
| username | VARCHAR | 50 | NOT NULL | - | 字母、数字、下划线，3-50字符 | 用户名 |
| password_hash | VARCHAR | 60 | NOT NULL | - | bcrypt格式哈希（60字符） | 密码哈希值 |
| email | VARCHAR | 100 | NOT NULL | - | 符合邮箱格式 | 电子邮箱 |
| phone | VARCHAR | 20 | NULL | NULL | 11位手机号 | 手机号码 |
| status | VARCHAR | 20 | NOT NULL | 'active' | 'active', 'frozen', 'deleted' | 账户状态 |
| created_at | DATETIME | - | NOT NULL | GETDATE() | - | 注册时间 |
| updated_at | DATETIME | - | NOT NULL | GETDATE() | - | 最后更新时间 |

**主码（PK）**：user_id  
**候选码（UNIQUE）**：username, email  
**外码（FK）**：无

### 1.2 商品表（Products）
**实体说明**：存储API Token套餐信息，包括价格和描述。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| product_id | INT | - | NOT NULL | - | 自增正整数 | 商品唯一标识 |
| name | VARCHAR | 100 | NOT NULL | - | 非空字符串，唯一 | 商品名称 |
| description | TEXT | - | NULL | NULL | - | 商品描述 |
| price | DECIMAL | (10,2) | NOT NULL | - | 大于0 | 单价（元） |
| model_provider | VARCHAR | 50 | NOT NULL | - | 'OpenAI', 'Claude', 'Gemini', 'Other' | AI模型提供商 |
| token_amount | INT | - | NOT NULL | - | 正整数 | 包含的Token数量 |
| required_upstream_tokens | INT | - | NOT NULL | - | 正整数 | 消耗上游账号的Token数量 |
| status | VARCHAR | 20 | NOT NULL | 'active' | 'active', 'inactive', 'discontinued' | 商品状态 |
| created_at | DATETIME | - | NOT NULL | GETDATE() | - | 创建时间 |

**主码（PK）**：product_id  
**候选码（UNIQUE）**：name, (model_provider, token_amount)  
**外码（FK）**：无

### 1.3 上游账号表（UpstreamAccount）
**实体说明**：存储从上游API提供商采购的账号信息。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| account_id | INT | - | NOT NULL | - | 自增正整数 | 账号唯一标识 |
| provider | VARCHAR | 50 | NOT NULL | - | 'OpenAI', 'Claude', 'Gemini', 'Other' | API提供商 |
| account_name | VARCHAR | 100 | NOT NULL | - | 非空字符串 | 账号名称/标识 |
| api_key | VARCHAR | 255 | NOT NULL | - | 加密存储（AES），样例用占位符 | API密钥 |
| total_quota | INT | - | NOT NULL | - | 正整数 | 总采购额度 |
| used_quota | INT | - | NOT NULL | 0 | 非负整数 | 已用额度 |
| safety_threshold | INT | - | NOT NULL | 1000 | 非负整数 | 安全阈值（低于此值触发补货） |
| status | VARCHAR | 20 | NOT NULL | 'active' | 'active', 'suspended', 'depleted', 'expired' | 账号状态 |
| expires_at | DATETIME | - | NULL | NULL | - | 过期时间 |
| created_at | DATETIME | - | NOT NULL | GETDATE() | - | 创建时间 |
| updated_at | DATETIME | - | NOT NULL | GETDATE() | - | 更新时间 |

**主码（PK）**：account_id  
**候选码（UNIQUE）**：(provider, account_name)  
**外码（FK）**：无

### 1.4 库存表（Inventory）
**实体说明**：存储每个上游账号的当前可用额度（号池库存）。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| inventory_id | INT | - | NOT NULL | - | 自增正整数 | 库存记录ID |
| account_id | INT | - | NOT NULL | - | - | 关联上游账号ID |
| current_quota | INT | - | NOT NULL | - | 非负整数 | 当前可用额度 |
| last_updated_at | DATETIME | - | NOT NULL | GETDATE() | - | 最后更新时间 |

**主码（PK）**：inventory_id  
**候选码（UNIQUE）**：account_id（每个账号一条库存记录）  
**外码（FK）**：account_id → UpstreamAccount(account_id)

### 1.5 库存流水表（InventoryLog）
**实体说明**：记录库存变动历史，用于审计和追踪。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| log_id | INT | - | NOT NULL | - | 自增正整数 | 流水ID |
| account_id | INT | - | NOT NULL | - | - | 关联账号ID |
| change_type | VARCHAR | 20 | NOT NULL | - | 'purchase', 'consumption', 'restock', 'adjustment' | 变动类型 |
| change_amount | INT | - | NOT NULL | - | 非零整数 | 变动数量（正数增加，负数减少） |
| reference_id | INT | - | NULL | NULL | - | 关联订单ID/补货任务ID |
| reference_type | VARCHAR | 20 | NULL | NULL | 'order', 'restock_task', 'manual' | 关联类型 |
| reason | VARCHAR | 255 | NULL | NULL | - | 变动原因说明 |
| operator_id | INT | - | NULL | NULL | - | 操作人ID（员工或系统） |
| created_at | DATETIME | - | NOT NULL | GETDATE() | - | 创建时间 |

**主码（PK）**：log_id  
**候选码（UNIQUE）**：无  
**外码（FK）**：account_id → UpstreamAccount(account_id)

### 1.6 订单表（Orders）
**实体说明**：存储用户订单信息，包括订单状态和总价。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| order_id | INT | - | NOT NULL | - | 自增正整数 | 订单唯一标识 |
| user_id | INT | - | NOT NULL | - | - | 下单用户ID |
| total_amount | DECIMAL | (10,2) | NOT NULL | - | 大于等于0 | 订单总金额 |
| total_tokens | INT | - | NOT NULL | - | 大于等于0 | 订单总Token数量 |
| status | VARCHAR | 20 | NOT NULL | 'pending' | 'pending', 'paid', 'cancelled', 'refunded' | 订单状态 |
| created_at | DATETIME | - | NOT NULL | GETDATE() | - | 创建时间 |
| paid_at | DATETIME | - | NULL | NULL | - | 支付时间 |

**主码（PK）**：order_id  
**候选码（UNIQUE）**：无  
**外码（FK）**：user_id → Users(user_id)

### 1.7 订单明细表（OrderDetails）
**实体说明**：存储订单中每个商品的详细信息。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| detail_id | INT | - | NOT NULL | - | 自增正整数 | 明细记录ID |
| order_id | INT | - | NOT NULL | - | - | 关联订单ID |
| product_id | INT | - | NOT NULL | - | - | 关联商品ID |
| quantity | INT | - | NOT NULL | 1 | 正整数 | 购买数量 |
| unit_price | DECIMAL | (10,2) | NOT NULL | - | 大于0 | 下单时单价 |
| subtotal | DECIMAL | (10,2) | NOT NULL | - | 大于等于0 | 小计金额 |
| tokens_per_unit | INT | - | NOT NULL | - | 正整数 | 每单位商品包含的Token数 |
| total_tokens | INT | - | NOT NULL | - | 大于等于0 | 该明细总Token数 |

**主码（PK）**：detail_id  
**候选码（UNIQUE）**：order_id + product_id（一个订单中同一商品只有一条明细）  
**外码（FK）**：order_id → Orders(order_id), product_id → Products(product_id)

### 1.8 员工表（Employees）
**实体说明**：存储内部员工信息，包括角色和权限。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| employee_id | INT | - | NOT NULL | - | 自增正整数 | 员工唯一标识 |
| name | VARCHAR | 50 | NOT NULL | - | 非空字符串 | 员工姓名 |
| role_id | INT | - | NOT NULL | - | - | 角色ID |
| account | VARCHAR | 50 | NOT NULL | - | 字母、数字、下划线 | 登录账号 |
| password_hash | VARCHAR | 60 | NOT NULL | - | bcrypt格式哈希（60字符） | 密码哈希值 |
| hire_date | DATE | - | NOT NULL | GETDATE() | - | 入职日期 |
| status | VARCHAR | 20 | NOT NULL | 'active' | 'active', 'inactive' | 在职状态 |

**主码（PK）**：employee_id  
**候选码（UNIQUE）**：account  
**外码（FK）**：role_id → Roles(role_id)

### 1.9 角色表（Roles）
**实体说明**：存储应用层角色描述，用于业务逻辑权限控制。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| role_id | INT | - | NOT NULL | - | 自增正整数 | 角色唯一标识 |
| role_name | VARCHAR | 50 | NOT NULL | - | 'admin', 'staff', 'customer' | 角色名称 |
| description | VARCHAR | 255 | NULL | NULL | - | 角色描述 |
| permissions | NVARCHAR(MAX) | - | NULL | NULL | JSON格式字符串 | 权限列表 |

**主码（PK）**：role_id  
**候选码（UNIQUE）**：role_name  
**外码（FK）**：无  
**约束**：CHECK (ISJSON(permissions) = 1)

**注意**：数据库层的权限使用SQL Server的CREATE ROLE + GRANT实现，此表仅用于应用层业务逻辑。

### 1.10 Token余额表（TokenBalances）
**实体说明**：存储用户在不同AI模型下的Token余额。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| balance_id | INT | - | NOT NULL | - | 自增正整数 | 余额记录ID |
| user_id | INT | - | NOT NULL | - | - | 用户ID |
| model_provider | VARCHAR | 50 | NOT NULL | - | 'OpenAI', 'Claude', 'Gemini', 'Other' | AI模型提供商 |
| remaining_tokens | INT | - | NOT NULL | 0 | 非负整数 | 剩余Token数量 |
| updated_at | DATETIME | - | NOT NULL | GETDATE() | - | 最后更新时间 |

**主码（PK）**：balance_id  
**候选码（UNIQUE）**：user_id + model_provider（每个用户每个模型一条余额记录）  
**外码（FK）**：user_id → Users(user_id)

### 1.11 Token使用记录表（TokenUsageLogs）
**实体说明**：记录用户每次API调用的Token使用情况（原始日志）。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| log_id | INT | - | NOT NULL | - | 自增正整数 | 日志ID |
| user_id | INT | - | NOT NULL | - | - | 用户ID |
| product_id | INT | - | NOT NULL | - | - | 使用的商品（套餐）ID |
| account_id | INT | - | NOT NULL | - | - | 消耗的上游账号ID |
| tokens_used | INT | - | NOT NULL | - | 正整数 | 本次使用Token数量 |
| upstream_tokens_consumed | INT | - | NOT NULL | - | 正整数 | 消耗的上游账号Token数量 |
| api_endpoint | VARCHAR | 255 | NULL | NULL | - | 调用的API端点 |
| used_at | DATETIME | - | NOT NULL | GETDATE() | - | 使用时间 |

**主码（PK）**：log_id  
**候选码（UNIQUE）**：无  
**外码（FK）**：user_id → Users(user_id), product_id → Products(product_id), account_id → UpstreamAccount(account_id)

### 1.12 使用汇总表（UsageSummary）
**实体说明**：按周期汇总用户Token使用量，用于预测分析。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| summary_id | INT | - | NOT NULL | - | 自增正整数 | 汇总ID |
| user_id | INT | - | NOT NULL | - | - | 用户ID |
| product_id | INT | - | NOT NULL | - | - | 商品ID |
| period_type | VARCHAR | 10 | NOT NULL | - | 'daily', 'weekly', 'monthly' | 周期类型 |
| period_start | DATE | - | NOT NULL | - | - | 周期开始日期 |
| period_end | DATE | - | NOT NULL | - | - | 周期结束日期 |
| total_tokens_used | INT | - | NOT NULL | 0 | 非负整数 | 周期内总Token使用量 |
| total_upstream_consumed | INT | - | NOT NULL | 0 | 非负整数 | 周期内总上游Token消耗 |
| request_count | INT | - | NOT NULL | 0 | 非负整数 | 周期内API调用次数 |
| last_updated_at | DATETIME | - | NOT NULL | GETDATE() | - | 最后更新时间 |

**主码（PK）**：summary_id  
**候选码（UNIQUE）**：user_id + product_id + period_type + period_start  
**外码（FK）**：user_id → Users(user_id), product_id → Products(product_id)

### 1.13 补货任务表（RestockTask）
**实体说明**：记录补货任务信息，用于触发和跟踪补货流程。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| task_id | INT | - | NOT NULL | - | 自增正整数 | 任务ID |
| account_id | INT | - | NOT NULL | - | - | 关联上游账号ID |
| trigger_reason | VARCHAR | 50 | NOT NULL | - | 'low_quota', 'scheduled', 'manual' | 触发原因 |
| restock_method | VARCHAR | 50 | NOT NULL | - | 'api_recharge', 'manual_purchase' | 补货方式 |
| target_amount | INT | - | NOT NULL | - | 正整数 | 目标补货数量 |
| actual_amount | INT | - | NULL | NULL | 非负整数 | 实际补货数量 |
| created_by | INT | - | NOT NULL | - | - | 创建人（员工ID） |
| assigned_to | INT | - | NULL | NULL | - | 执行人（员工ID） |
| status | VARCHAR | 20 | NOT NULL | 'pending' | 'pending', 'in_progress', 'completed', 'failed' | 任务状态 |
| created_at | DATETIME | - | NOT NULL | GETDATE() | - | 创建时间 |
| completed_at | DATETIME | - | NULL | NULL | - | 完成时间 |
| notes | TEXT | - | NULL | NULL | - | 备注 |

**主码（PK）**：task_id  
**候选码（UNIQUE）**：无  
**外码（FK）**：account_id → UpstreamAccount(account_id), created_by → Employees(employee_id), assigned_to → Employees(employee_id)

### 1.14 异常记录表（ExceptionLog）
**实体说明**：记录系统异常和错误信息。
| 字段名 | 类型 | 长度/精度 | 是否允许空 | 默认值 | 域（取值范围/枚举） | 含义 |
|--------|------|-----------|------------|--------|-------------------|------|
| exception_id | INT | - | NOT NULL | - | 自增正整数 | 异常ID |
| exception_type | VARCHAR | 50 | NOT NULL | - | 'api_error', 'payment_error', 'inventory_error', 'system_error' | 异常类型 |
| related_table | VARCHAR | 50 | NULL | NULL | - | 关联表名 |
| related_id | INT | - | NULL | NULL | - | 关联记录ID |
| error_message | TEXT | - | NOT NULL | - | - | 错误信息 |
| error_detail | TEXT | - | NULL | NULL | - | 简要错误描述 |
| occurred_at | DATETIME | - | NOT NULL | GETDATE() | - | 发生时间 |
| handled_by | INT | - | NULL | NULL | - | 处理人（员工ID） |
| handle_result | VARCHAR | 50 | NULL | NULL | 'resolved', 'ignored', 'escalated' | 处理结果 |
| handle_notes | TEXT | - | NULL | NULL | - | 处理备注 |
| handled_at | DATETIME | - | NULL | NULL | - | 处理时间 |

**主码（PK）**：exception_id  
**候选码（UNIQUE）**：无  
**外码（FK）**：handled_by → Employees(employee_id)

**字段说明**：error_message存储原始错误信息，error_detail存储人工补充的说明或处理建议。

## 2. 样例元组

### 2.1 用户表（Users）
```sql
INSERT INTO Users (username, password_hash, email, phone, status, created_at, updated_at)
VALUES
('zhangsan', '$2b$12$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 'zhangsan@example.com', '13800138001', 'active', '2026-09-01 10:00:00', '2026-09-01 10:00:00'),
('lisi', '$2b$12$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 'lisi@example.com', '13800138002', 'active', '2026-09-02 11:30:00', '2026-09-02 11:30:00'),
('wangwu', '$2b$12$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 'wangwu@example.com', NULL, 'frozen', '2026-09-03 09:15:00', '2026-09-05 14:20:00');
```

### 2.2 商品表（Products）
```sql
INSERT INTO Products (name, description, price, model_provider, token_amount, required_upstream_tokens, status, created_at)
VALUES
('GPT-4 100K Token包', 'OpenAI GPT-4模型，100,000 Token', 150.00, 'OpenAI', 100000, 120000, 'active', '2026-09-01 08:00:00'),
('Claude 50K Token包', 'Anthropic Claude模型，50,000 Token', 80.00, 'Claude', 50000, 60000, 'active', '2026-09-01 08:00:00'),
('Gemini 200K Token包', 'Google Gemini模型，200,000 Token', 200.00, 'Gemini', 200000, 240000, 'active', '2026-09-01 08:00:00');
```

### 2.3 上游账号表（UpstreamAccount）
```sql
INSERT INTO UpstreamAccount (provider, account_name, api_key, total_quota, used_quota, safety_threshold, status, expires_at, created_at, updated_at)
VALUES
('OpenAI', '主账号-001', 'enc:U2FsdGVkX1+abcdefghijklmnopqrstuvwxyz123456', 10000000, 3000000, 500000, 'active', '2027-09-01 00:00:00', '2026-09-01 07:00:00', '2026-09-10 14:30:00'),
('Claude', '主账号-001', 'enc:U2FsdGVkX1+abcdefghijklmnopqrstuvwxyz123456', 5000000, 1500000, 300000, 'active', '2027-09-01 00:00:00', '2026-09-01 07:00:00', '2026-09-11 09:20:00'),
('Gemini', '主账号-001', 'enc:U2FsdGVkX1+abcdefghijklmnopqrstuvwxyz123456', 8000000, 2000000, 400000, 'active', '2027-09-01 00:00:00', '2026-09-01 07:00:00', '2026-09-12 16:45:00');
```

### 2.4 库存表（Inventory）
```sql
INSERT INTO Inventory (account_id, current_quota, last_updated_at)
VALUES
(1, 7000000, '2026-09-10 14:30:00'),
(2, 3500000, '2026-09-11 09:20:00'),
(3, 6000000, '2026-09-12 16:45:00');
```

### 2.5 库存流水表（InventoryLog）
```sql
INSERT INTO InventoryLog (account_id, change_type, change_amount, reference_id, reference_type, reason, operator_id, created_at)
VALUES
(1, 'purchase', 10000000, NULL, NULL, '初始采购', NULL, '2026-09-01 07:00:00'),
(1, 'consumption', -120000, 1, 'order', '订单#1消耗', NULL, '2026-09-10 14:35:00'),
(2, 'purchase', 5000000, NULL, NULL, '初始采购', NULL, '2026-09-01 07:00:00'),
(2, 'consumption', -60000, 2, 'order', '订单#2消耗', NULL, '2026-09-11 09:25:00');
```

### 2.6 订单表（Orders）
```sql
INSERT INTO Orders (user_id, total_amount, total_tokens, status, created_at, paid_at)
VALUES
(1, 150.00, 100000, 'paid', '2026-09-10 14:30:00', '2026-09-10 14:35:00'),
(2, 80.00, 50000, 'paid', '2026-09-11 09:20:00', '2026-09-11 09:25:00'),
(1, 200.00, 200000, 'pending', '2026-09-12 16:45:00', NULL);
```

### 2.7 订单明细表（OrderDetails）
```sql
INSERT INTO OrderDetails (order_id, product_id, quantity, unit_price, subtotal, tokens_per_unit, total_tokens)
VALUES
(1, 1, 1, 150.00, 150.00, 100000, 100000),
(2, 2, 1, 80.00, 80.00, 50000, 50000),
(3, 3, 1, 200.00, 200.00, 200000, 200000);
```

### 2.8 员工表（Employees）
```sql
INSERT INTO Employees (name, role_id, account, password_hash, hire_date, status)
VALUES
('张经理', 1, 'admin_zhang', '$2b$12$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', '2026-01-01', 'active'),
('李客服', 2, 'staff_li', '$2b$12$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', '2026-03-15', 'active'),
('王运营', 2, 'staff_wang', '$2b$12$abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', '2026-06-20', 'active');
```

### 2.9 角色表（Roles）
```sql
INSERT INTO Roles (role_name, description, permissions)
VALUES
('admin', '系统管理员，拥有所有权限', '{"all": true}'),
('staff', '客服/运营，处理订单和用户问题', '{"orders": "read/write", "users": "read", "inventory": "read"}'),
('customer', '普通用户，购买和使用Token', '{"products": "read", "orders": "create", "balance": "read"}');
```

### 2.10 Token余额表（TokenBalances）
```sql
INSERT INTO TokenBalances (user_id, model_provider, remaining_tokens, updated_at)
VALUES
(1, 'OpenAI', 100000, '2026-09-10 14:35:00'),
(1, 'Claude', 50000, '2026-09-10 14:35:00'),
(2, 'Claude', 50000, '2026-09-11 09:25:00');
```

### 2.11 Token使用记录表（TokenUsageLogs）
```sql
INSERT INTO TokenUsageLogs (user_id, product_id, account_id, tokens_used, upstream_tokens_consumed, api_endpoint, used_at)
VALUES
(1, 1, 1, 1500, 1800, '/v1/chat/completions', '2026-09-10 15:00:00'),
(1, 1, 1, 2000, 2400, '/v1/embeddings', '2026-09-10 16:30:00'),
(2, 2, 2, 800, 960, '/v1/chat/completions', '2026-09-11 10:15:00');
```

### 2.12 使用汇总表（UsageSummary）
```sql
INSERT INTO UsageSummary (user_id, product_id, period_type, period_start, period_end, total_tokens_used, total_upstream_consumed, request_count, last_updated_at)
VALUES
(1, 1, 'daily', '2026-09-10', '2026-09-10', 3500, 4200, 2, '2026-09-10 23:59:59'),
(2, 2, 'daily', '2026-09-11', '2026-09-11', 800, 960, 1, '2026-09-11 23:59:59'),
(1, 1, 'weekly', '2026-09-08', '2026-09-14', 3500, 4200, 2, '2026-09-14 23:59:59');
```

### 2.13 补货任务表（RestockTask）
```sql
INSERT INTO RestockTask (account_id, trigger_reason, restock_method, target_amount, actual_amount, created_by, assigned_to, status, created_at, completed_at, notes)
VALUES
(1, 'low_quota', 'api_recharge', 2000000, 2000000, 1, 2, 'completed', '2026-09-05 10:00:00', '2026-09-05 10:30:00', 'OpenAI账号额度不足，已自动充值'),
(2, 'scheduled', 'manual_purchase', 1000000, NULL, 1, NULL, 'pending', '2026-09-15 09:00:00', NULL, '每月定期采购Claude额度');
```

### 2.14 异常记录表（ExceptionLog）
```sql
INSERT INTO ExceptionLog (exception_type, related_table, related_id, error_message, error_detail, occurred_at, handled_by, handle_result, handle_notes, handled_at)
VALUES
('api_error', 'TokenUsageLogs', 1, 'OpenAI API调用失败：Rate limit exceeded', 'API速率限制超限，需等待或切换账号', '2026-09-10 15:05:00', 2, 'resolved', '已重试调用，成功', '2026-09-10 15:10:00'),
('inventory_error', 'Inventory', 1, '库存扣减失败：额度不足', '当前可用额度不足，需补货', '2026-09-12 17:00:00', NULL, 'ignored', '系统自动触发补货任务', '2026-09-12 17:05:00');
```

## 3. 表关系总结
- **Users** ↔ **Orders**：一个用户可以有多个订单（1:N）
- **Orders** ↔ **OrderDetails**：一个订单可以有多个明细（1:N）
- **Products** ↔ **OrderDetails**：一个商品可以被多个订单包含（1:N）
- **UpstreamAccount** ↔ **Inventory**：一个上游账号对应一条库存记录（1:1）
- **UpstreamAccount** ↔ **InventoryLog**：一个上游账号可以有多条库存流水（1:N）
- **UpstreamAccount** ↔ **TokenUsageLogs**：一个上游账号可以有多条使用记录（1:N）
- **Employees** ↔ **Roles**：一个员工属于一个角色（N:1）
- **Users** ↔ **TokenBalances**：一个用户可以有多个Token余额记录（按模型区分）（1:N）
- **Users** ↔ **TokenUsageLogs**：一个用户可以有多条使用记录（1:N）
- **Products** ↔ **TokenUsageLogs**：一个商品可以有多条使用记录（1:N）
- **Users** ↔ **UsageSummary**：一个用户可以有多条汇总记录（1:N）
- **UpstreamAccount** ↔ **RestockTask**：一个上游账号可以有多个补货任务（1:N）
- **Employees** ↔ **RestockTask**：一个员工可以创建/执行多个补货任务（1:N）
- **Employees** ↔ **ExceptionLog**：一个员工可以处理多个异常（1:N）

## 4. 设计说明
1. **库存三层语义**：
   - **采购总量**：UpstreamAccount.total_quota - 从上游买了多少额度
   - **累计已用**：UpstreamAccount.used_quota - 历史上总共用了多少
   - **实时可用**：Inventory.current_quota - 现在还能用多少
   三者语义不同，不冗余。总采购量相对稳定，累计已用只增不减，实时可用随消耗和补货变动。

2. **商品→上游额度换算**：通过Products.required_upstream_tokens字段，明确每个商品消耗的上游Token数量。例如用户买一个100K Token的套餐，实际消耗上游120K Token（因为转发有损耗/加价）。required_upstream_tokens记录这个换算比例。

3. **流水记录**：InventoryLog完整记录库存变动历史，支持审计和追踪。

4. **预测支持**：UsageSummary表按周期汇总使用量，为第四阶段预测提供数据基础。支持daily、weekly、monthly多粒度，daily做短期预测，weekly做趋势分析。

5. **补货任务**：RestockTask表为第三阶段补货事务提供操作对象。补货有两种方式：API自动充值（适用于支持在线充值的上游）、人工采购（适用于需要人工操作的供应商）。第三阶段会分别实现这两种补货事务。

6. **异常管理**：ExceptionLog表确保系统异常可追踪、可处理。

7. **权限分层**：应用层角色表（Roles）与数据库层权限（CREATE ROLE + GRANT）分离，职责清晰。应用层角色用于业务逻辑权限控制，数据库层权限用于SQL Server的安全控制。

8. **数据完整性**：所有外键关系明确，确保数据一致性。Orders.total_tokens = SUM(OrderDetails.total_tokens)，这是第三阶段做事务时的重要约束。

9. **Token字段冗余说明**：Orders.total_tokens存储订单总Token数，OrderDetails.total_tokens存储明细总Token数。这是合理的冗余（订单表存汇总，明细表存分项），便于查询和统计。