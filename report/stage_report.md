# 第一阶段 v0.1 阶段报告

> 项目：API Token 中转站数据库　阶段：第一阶段（v0.1）
> 环境：SQL Server 2025 Express 17.0.1135.8 / `localhost\SQLEXPRESS` / Windows 身份验证
> 正式脚本：[`sql/`](../sql/README.md)　复现入口：[`tools/run_v01.ps1`](../tools/run_v01.ps1)

## 一、设计思路

### 1. 经营场景与业务流程

本项目模拟 API Token 中转站。平台向用户销售不同 AI provider 的 Token 套餐，用户支付后获得对应模型余额，之后通过平台调用 API；平台从上游账号额度中提供服务，并记录库存、库存流水、使用量、补货和异常。

核心闭环：

```text
浏览商品 → 创建订单 → 支付 → 增加用户 Token 余额
→ API 调用 → 扣减用户余额和上游库存
→ 记录调用日志/库存流水 → 统计汇总 → 低库存补货/异常处理
```

经营角色包括店长、店员、会员和游客。店长负责商品、库存、订单和经营分析；店员读取经营数据、通过工作队列切换订单状态并联系客户；会员只能访问商品和本人业务数据；游客只浏览在售商品。

销售统计统一只计算 `Orders.status='paid'`，历史销售额采用 `OrderDetails.subtotal` 的下单快照，不用当前商品价格重算历史订单。

### 2. 数据边界：哪些信息进入数据库，哪些暂不进入

进入数据库的信息包括：用户账户元数据、商品套餐、订单与明细、上游账号元数据、库存与库存流水、Token 余额、调用用量、日/周/月使用汇总、员工与角色、补货任务、异常处理结果。这些信息直接参与交易、额度控制、审计或经营分析。

暂不进入数据库的信息包括：用户密码明文、真实 API Key、Prompt 与完整 API 请求/响应、第三方支付详细流水、设备/IP、图片文件等。原因分别是安全、隐私、课程范围和存储成本。本项目只保存密码哈希；样例 API Key 使用 `DEMO_NOT_A_REAL_API_KEY_*` 明确占位符。

真实注册、支付、退款、充值、补货事务、并发控制和应用登录映射也暂不作为 v0.1 的完整业务事务实现，它们属于后续阶段。

### 3. 表设计、主码、候选码与外码

14 张表按“业务实体有独立身份、关系通过外键表达、天然唯一属性使用候选码”设计。核心键如下：

| 表 | 主码 | 主要候选码 | 主要外码 |
|---|---|---|---|
| Users | `user_id` | `username`、`email` | 无 |
| Products | `product_id` | `name`、(`model_provider`,`token_amount`) | 无 |
| UpstreamAccount | `account_id` | (`provider`,`account_name`) | 无 |
| Inventory | `inventory_id` | `account_id` | `account_id → UpstreamAccount` |
| InventoryLog | `log_id` | 无 | `account_id → UpstreamAccount`、`operator_id → Employees` |
| Orders | `order_id` | 无 | `user_id → Users` |
| OrderDetails | `detail_id` | (`order_id`,`product_id`) | `order_id → Orders`、`product_id → Products` |
| Employees | `employee_id` | `account` | `role_id → Roles` |
| Roles | `role_id` | `role_name` | 无 |
| TokenBalances | `balance_id` | (`user_id`,`model_provider`) | `user_id → Users` |
| TokenUsageLogs | `log_id` | 无 | `user_id → Users`、`product_id → Products`、`account_id → UpstreamAccount` |
| UsageSummary | `summary_id` | (`user_id`,`product_id`,`period_type`,`period_start`) | `user_id → Users`、`product_id → Products` |
| RestockTask | `task_id` | 无 | `account_id → UpstreamAccount`、`created_by/assigned_to → Employees` |
| ExceptionLog | `exception_id` | 无 | `handled_by → Employees` |

主码统一使用整数 ID，便于连接、索引和固定样例数据复现；候选码用于约束现实世界中应唯一的用户名、邮箱、员工账号、角色名和账号/套餐组合；外码保证订单、库存、使用记录等不能指向不存在的实体。

`Inventory` 关联 `UpstreamAccount` 而不是 `Products`，因为库存表示的是“上游账号还剩多少可用 Token”，产品只是销售层套餐。`Orders.total_tokens` 与 `OrderDetails.total_tokens` 是受控冗余：前者是订单汇总，后者是明细分项，`verify.sql` 会逐订单核对两者一致。

字段类型的选择也有明确理由：金额一律用 `DECIMAL(10,2)` 而非 `FLOAT`，避免浮点近似误差累积；中文业务文本（商品名、错误描述、员工姓名）用 `NVARCHAR`；时间戳统一 `DATETIME2(0)`；`Roles.permissions` 用 `NVARCHAR(MAX)` 承载 JSON 并配 `ISJSON` CHECK；`password_hash` 最多 60 字符以容纳真实 bcrypt 格式；API Key 列存 `DEMO_NOT_A_REAL_API_KEY_*` 占位符，真实密钥不入库。

### 4. 实体关系图

由 [`sql/01_create_tables.sql`](../sql/01_create_tables.sql) 生成，列出主码、外码与候选码，业务字段只保留代表性列。

```mermaid
erDiagram
    ROLES ||--o{ EMPLOYEES : "分配角色"
    USERS ||--o{ ORDERS : "创建订单"
    USERS ||--o{ TOKENBALANCES : "持有余额"
    USERS ||--o{ TOKENUSAGELOGS : "产生调用"
    USERS ||--o{ USAGESUMMARY : "按周期汇总"
    ORDERS ||--|{ ORDERDETAILS : "包含明细"
    PRODUCTS ||--o{ ORDERDETAILS : "被购买"
    PRODUCTS ||--o{ TOKENUSAGELOGS : "被调用"
    PRODUCTS ||--o{ USAGESUMMARY : "被汇总"
    UPSTREAMACCOUNT ||--|| INVENTORY : "剩余额度"
    UPSTREAMACCOUNT ||--o{ INVENTORYLOG : "额度流水"
    UPSTREAMACCOUNT ||--o{ TOKENUSAGELOGS : "提供上游消耗"
    UPSTREAMACCOUNT ||--o{ RESTOCKTASK : "补货对象"
    EMPLOYEES ||--o{ INVENTORYLOG : "操作人"
    EMPLOYEES ||--o{ RESTOCKTASK : "创建或认领"
    EMPLOYEES ||--o{ EXCEPTIONLOG : "处理人"

    ROLES {
        int role_id PK
        varchar role_name UK "admin staff customer"
        nvarchar permissions "JSON"
    }
    USERS {
        int user_id PK
        varchar username UK
        varchar email UK
        varchar password_hash "只存哈希"
        varchar phone
        varchar status "active frozen deleted"
        datetime2 created_at
    }
    PRODUCTS {
        int product_id PK
        nvarchar name UK
        decimal price
        varchar model_provider UK "候选码之一"
        int token_amount UK "与 provider 组成复合候选码"
        int required_upstream_tokens
        varchar status
    }
    UPSTREAMACCOUNT {
        int account_id PK
        varchar provider UK "与 account_name 组成复合候选码"
        nvarchar account_name UK
        nvarchar api_key "教学占位符"
        bigint total_quota
        bigint used_quota
        bigint safety_threshold
        varchar status
        datetime2 expires_at
    }
    INVENTORY {
        int inventory_id PK
        int account_id FK "候选码"
        bigint current_quota
        datetime2 last_updated_at
    }
    EMPLOYEES {
        int employee_id PK
        nvarchar name
        int role_id FK
        varchar account UK
        varchar password_hash
        date hire_date
    }
    ORDERS {
        int order_id PK
        int user_id FK
        decimal total_amount
        bigint total_tokens
        varchar status
        datetime2 paid_at
    }
    ORDERDETAILS {
        int detail_id PK
        int order_id FK "候选码"
        int product_id FK "候选码"
        int quantity
        decimal unit_price
        decimal subtotal
        int tokens_per_unit
        bigint total_tokens
    }
    INVENTORYLOG {
        int log_id PK
        int account_id FK
        varchar change_type "purchase consumption restock adjustment"
        bigint change_amount
        varchar reference_type
        int operator_id FK
        datetime2 created_at
    }
    TOKENBALANCES {
        int balance_id PK
        int user_id FK "候选码"
        varchar model_provider FK "与 user_id 组成复合候选码"
        bigint remaining_tokens
        datetime2 updated_at
    }
    TOKENUSAGELOGS {
        int log_id PK
        int user_id FK
        int product_id FK
        int account_id FK
        int tokens_used
        int upstream_tokens_consumed
        varchar api_endpoint
        datetime2 used_at
    }
    USAGESUMMARY {
        int summary_id PK
        int user_id FK "候选码"
        int product_id FK "候选码"
        varchar period_type "daily weekly monthly"
        date period_start "候选码"
        date period_end
        bigint total_tokens_used
        bigint total_upstream_consumed
        int request_count
    }
    RESTOCKTASK {
        int task_id PK
        int account_id FK
        varchar trigger_reason
        varchar restock_method
        bigint target_amount
        bigint actual_amount
        int created_by FK
        int assigned_to FK
        varchar status
    }
    EXCEPTIONLOG {
        int exception_id PK
        varchar exception_type
        varchar related_table
        int related_id
        nvarchar error_message
        nvarchar error_detail
        int handled_by FK
        varchar handle_result
        datetime2 handled_at
    }
```

关系基数与语义：

| 关系 | 基数 | 说明 |
|---|---|---|
| `UPSTREAMACCOUNT` → `INVENTORY` | 1 : 1 | `Inventory.account_id` 是候选码，一个上游账号只有一条库存记录；库存表示上游账号剩余可用 Token，不是商品件数 |
| `ORDERS` → `ORDERDETAILS` | 1 : N | 一个订单至少一条明细；`(order_id, product_id)` 是候选码，同一订单不重复出现同一商品 |
| `USERS` → `TOKENBALANCES` | 1 : N | 一个会员按 `model_provider` 持有多条余额，复合候选码 `(user_id, model_provider)` |
| `USERS`/`PRODUCTS` → `USAGESUMMARY` | 1 : N | 汇总粒度为用户 × 商品 × 周期类型 × 周期起点，用于经营统计与后续预测 |
| `TOKENUSAGELOGS` | 多外码 | 一次调用同时关联会员、商品和提供服务的上游账号，是调用量与上游消耗对账的枢纽 |
| `EMPLOYEES` → `INVENTORYLOG` / `RESTOCKTASK` / `EXCEPTIONLOG` | 1 : N | 员工操作留痕；`operator_id`、`created_by/assigned_to`、`handled_by` 均可为空，表示系统自动写入 |

冗余与对账关系：`Orders.total_tokens = SUM(OrderDetails.total_tokens)`、`Orders.total_amount = SUM(OrderDetails.subtotal)`（同一订单内）、`Inventory.current_quota = UpstreamAccount.total_quota - used_quota = SUM(InventoryLog.change_amount)`。这三项由 [`sql/verify.sql`](../sql/verify.sql) 的 VFY02、VFY05、VFY09 逐条对账，任何一项不一致都会让流水线以非零退出码失败。

### 5. 完整性约束设计

本阶段同时使用实体完整性、参照完整性、域完整性和跨列业务约束：

| 约束类型 | 作用 | 代表约束 |
|---|---|---|
| PK / UNIQUE | 实体与候选码唯一 | `PK_Orders`、`UQ_Users_username`、`UQ_Users_email`、`UQ_Products_name`、`UQ_Products_provider_tokens`、`UQ_OrderDetails_order_product`、`UQ_TokenBalances_user_provider`、`UQ_Inventory_account`、`UQ_UpstreamAccount_provider_name`、`UQ_UsageSummary_key` |
| FK | 引用真实父实体 | `FK_Orders_Users`、`FK_OrderDetails_Products`、`FK_Inventory_UpstreamAccount`、`FK_TokenUsageLogs_Account`、`FK_RestockTask_CreatedBy` |
| NOT NULL / DEFAULT | 必要字段与稳定初态 | `Orders.status DEFAULT 'pending'`、`Products.status DEFAULT 'active'`、`Users.created_at DEFAULT SYSDATETIME()` |
| CHECK（域） | 价格、数量、枚举、JSON、非负额度 | `CK_Products_price`、`CK_Users_status`、`CK_Roles_permissions_json`、`CK_Inventory_current_quota`、`CK_TokenBalances_remaining` |
| CHECK（跨列） | 第四周新增 3 个 | `CK_OrderDetails_subtotal_formula`、`CK_OrderDetails_tokens_formula`、`CK_Orders_payment_time` |

三个跨列 CHECK 覆盖了原先只能靠应用层保证的业务不变量：

- `CK_OrderDetails_subtotal_formula`：`subtotal = quantity * unit_price`
- `CK_OrderDetails_tokens_formula`：`total_tokens = quantity * tokens_per_unit`
- `CK_Orders_payment_time`：`status = 'paid'` 时 `paid_at` 必填

订单头与明细汇总、上游账号与库存与流水属于跨表规则，普通 CHECK 无法直接可靠表达（CHECK 只能引用同表列，且子查询不受支持），因此通过 `verify.sql` 独立对账，并留给后续事务阶段用触发器或存储过程维护。

#### 正反例：`constraint.sql` 的 C01～C14

用例驱动器在事务中执行每条语句，捕获实际错误号与报错文本，只有**错误号匹配且报错文本包含预期约束名**才算 PASS，避免“只要报错就算成功”。合法用例（C01、C02）在事务中验证 DEFAULT 生效后回滚。

| 用例 | 类型 | 操作 | 预期错误号 | 命中约束 |
|---|---|---|---|---|
| C01 | 正例 | 插入商品，省略 `status`/`description` | 无（断言 `status='active'`、`created_at` 非空、`description` 为 NULL） | DEFAULT |
| C02 | 正例 | 插入订单，省略 `status`/`paid_at` | 无（断言 `status='pending'`、`paid_at` 为 NULL） | DEFAULT |
| C03 | 反例 | `IDENTITY_INSERT ON` 后插入重复 `order_id=1` | 2627 | `PK_Orders` |
| C04 | 反例 | 插入已存在的 `username='user001'` | 2627 | `UQ_Users_username` |
| C05 | 反例 | 插入 `user_id=999999` 的订单 | 547 | `FK_Orders_Users` |
| C06 | 反例 | 插入 `price=-1` 的商品 | 547 | `CK_Products_price` |
| C07 | 反例 | 插入 `name=NULL` 的商品 | 515 | NOT NULL（不指定约束名） |
| C08 | 反例 | 把 `OrderDetails.subtotal` 加 0.01 | 547 | `CK_OrderDetails_subtotal_formula` |
| C09 | 反例 | 把 `OrderDetails.total_tokens` 加 1 | 547 | `CK_OrderDetails_tokens_formula` |
| C10 | 反例 | 把一个 `paid` 订单的 `paid_at` 置 NULL | 547 | `CK_Orders_payment_time` |
| C11 | 反例 | 删除仍有订单的用户 `user_id=1` | 547 | FK（参照完整性，不指定约束名） |
| C12 | 反例 | 复制商品但保持 `model_provider`+`token_amount` 相同 | 2627 | `UQ_Products_provider_tokens` |
| C13 | 反例 | 复制同一订单的同一商品明细行 | 2627 | `UQ_OrderDetails_order_product` |
| C14 | 反例 | 把 `staff` 角色的 `permissions` 改成 `'not-json'` | 547 | `CK_Roles_permissions_json` |

C12～C14 是本轮补充的三个反例，用来证明候选码与 JSON 域约束确实生效：仅靠“有约束”无法说明约束有效，只有实际触发并命中指定约束名才算验证通过。

### 6. 角色与权限划分及正反例

数据库层使用四个 SQL Server DATABASE ROLE，遵循最小权限原则：

| 角色 | 允许 | 明确禁止 |
|---|---|---|
| `hub_manager` | 14 张业务表 CRUD、7 个共享视图 | CREATE TABLE、CONTROL、db_owner、sysadmin |
| `hub_staff` | 经营视图（订单明细、销量、会员消费、库存、客服视图）；仅更新 `v_StaffOrderQueue.status` | 直接改商品价格、任意基表 CRUD、读取 `dbo.Users` 密码哈希 |
| `hub_customer` | 商品目录、本人订单/余额/用量 | 读取 Orders/TokenBalances/UpstreamAccount/Users 等基表、读取客服视图 |
| `hub_guest` | 在售商品目录 | 订单和个人数据 |

#### 正反例：`role.sql` 的 R01～R17

同样在事务中以 `EXECUTE AS` 切换到对应数据库用户执行，断言权限行为而不是只看是否报错。

| 用例 | 执行身份 | 类型 | 操作 | 预期 |
|---|---|---|---|---|
| R01 | `hub_guest_demo` | 正例 | 读 `v_ProductCatalog` | 成功，返回 10 行 |
| R02 | `hub_guest_demo` | 反例 | `SELECT order_id FROM dbo.Orders` | 拒绝，错误 229 |
| R03 | `hub_staff_demo` | 正例 | 读 `v_OrderDetail` | 成功，返回 184 行 |
| R04 | `hub_staff_demo` | 反例 | `UPDATE dbo.Products SET price=price+1` | 拒绝，错误 229（店员不得改价） |
| R05 | `hub_staff_demo` | 正例 | 经 `v_StaffOrderQueue` 把 pending 订单改 cancelled | 成功，且 `@@ROWCOUNT=1` |
| R06 | `hub_user_1` | 正例 | 读 `v_MyOrders` | 成功，13 行且全部 `user_id=1` |
| R07 | `hub_user_2` | 正例 | 读 `v_MyOrders` | 成功，15 行且全部 `user_id=2` |
| R08 | `hub_user_1` | 反例 | `SELECT order_id FROM dbo.Orders` | 拒绝，错误 229 |
| R09 | `hub_user_1` | 反例 | `SELECT api_key FROM dbo.UpstreamAccount` | 拒绝，错误 229 |
| R10 | `hub_user_1` | 正例 | 断言看不到他人数据 | `v_MyOrders` 无 `user_id=2`；`v_MyBalances`/`v_MyUsage` 非空且均属本人 |
| R11 | `hub_manager_demo` | 正例 | `UPDATE dbo.Products SET price=price+1` | 成功，且 `@@ROWCOUNT=1` |
| R12 | `hub_manager_demo` | 反例 | 检查 `HAS_PERMS_BY_NAME` 是否含 `CREATE TABLE`/`CONTROL` | 断言两项均为否（店长不是高权限角色） |
| R13 | `hub_staff_demo` | 反例 | `UPDATE dbo.v_StaffOrderQueue SET user_id=...` | 拒绝，错误 230（无该列的 UPDATE 权限） |
| R14 | `hub_staff_demo` | 正例 | 读 `v_CustomerService` | 成功，40 行；视图不含 `password_hash`/`api_key` |
| R15 | `hub_staff_demo` | 反例 | `SELECT password_hash FROM dbo.Users` | 拒绝，错误 229（客服必须走不含密码哈希的视图） |
| R16 | `hub_user_1` | 反例 | `SELECT email FROM dbo.v_CustomerService` | 拒绝，错误 229（会员看不到他人联系方式） |
| R17 | `hub_manager_demo` | 正例 | 读 `v_CustomerService` | 成功，40 行 |

这组正反例覆盖了三层边界：角色之间的横向隔离（R02/R08/R09/R16）、同一角色内部的权限粒度（R04 与 R11 对比商品改价、R05 与 R13 对比队列视图的列级授权、R14 与 R15 对比客服视图与基表）、以及角色自身的权限上界（R12 证明店长没有被授予 DDL 或 CONTROL）。R05 与 R13 是最能说明列级授权的一对：店员能改 `v_StaffOrderQueue.status`，但改 `user_id` 会被 230 拒绝。

会员隔离不依赖调用者可随意设置的变量，而是让数据库用户 `hub_user_1` / `hub_user_2` 通过 `USER_NAME()` 映射到业务用户 1 / 2，并且不向会员开放相关基表 SELECT。

**为什么 v0.1 不给会员开下单/支付写权限。** 第一周的经营流程里会员可以下单、支付并修改本人资料，但 v0.1 是数据原型而不是应用：直接 `GRANT INSERT ON Orders TO hub_customer` 会让任何会员都能给任意 `user_id` 建单，绕过订单汇总、Token 换算和支付时间规则。因此会员写操作统一放到第三阶段的存储过程（`sp_PlaceOrder`、`sp_PayOrder`、`sp_UpdateProfile`、`sp_RestockOrder`），由过程内部校验 `USER_NAME()` 与目标 `user_id` 一致并在同一事务内维护余额与流水。本阶段只交付会员只读能力，写能力作为已知差异写在本报告第 2 节和 `report/role_workflow.md`。

角色到数据库对象的完整链路见 [`role_workflow.md`](role_workflow.md)。

## 二、实验过程

### 1. 第一至四周成果与目录

第一周确定 Token 中转经营场景、角色与数据边界；第二周形成 14 表关系模式、属性和键；第三周完成 SQL Server 建库、样例和 CRUD；第四周完成多表查询、统计视图、约束和角色授权。

各周原始过程材料保留在 [archive](../archive/README.md)。正式交付只使用根 sql、tools、report、docs 和 result；正式生成器不依赖归档材料。第四周要求逐条映射见 [任务书索引](../docs/requirements/README.md)。

### 2. 2026-10-02 修复过程

审查发现旧数据有 20 个订单、402 次调用早于注册；225 次调用晚于账号到期；用户 32 的调用发生在首次付款前，导致一次历史余额 -2000。旧验收只检查最终余额，未捕获业务时间错误。

修复将注册时间安排到最早订单前，按 paid_at 的累计到账额度安排消费，调用遇到已到期账号时改用同 provider 的有效账号。保留金额和 Token 总量，不为保留旧签名迁就错误数据。当前快照 suspended/expired 状态不用于推断过去状态，账号有效期按创建和到期时间核对。

新增 VFY12 检查注册、账号有效期与 provider；VFY13 用窗口累计和检查每个充值/消费事件余额。同秒付款先到账再扣款。VFY03 逐表逐权限检查四项 CRUD，VFY14 通过演示用户上下文检查实际基表权限，防止用户直接授权绕过仅检查角色的旧逻辑。

证据脚本改为对结果、错误号、必要约束名和回滚恢复进行断言；不再无条件打印 PASS。截图工具检查 sqlcmd 失败并将实际输出控件分页，完整日志另存。首次控件捕获因未完成显示布局生成空白图，视觉检查发现后改为屏幕外显示、完成布局再捕获；该尝试保留在 archive/implementation-attempts。

最终 22 个回归测试、ruff 检查与格式检查通过。生成器与 SQL 回归分别注入错误样例、缺权限和直接用户授权，确认指定错误能被捕获，之后回滚反例。修复原因和预防规则同步进入 [ROADMAP](../ROADMAP.md)、[CLAUDE](../CLAUDE.md) 及 [AI 日志](../docs/ai_usage_log.md)。

### 3. 实际运行与结果

本机 SQL Server Express 17.0.1135.8 使用 Windows 集成认证。两个新空库 TokenHubDB_v01_FinalA、TokenHubDB_v01_FinalB 完整执行当前版本，日志见 [result](../result/README.md)。

| 项目 | 实测结果 |
|---|---|
| 业务表 / 视图 / 数据库角色 / 演示用户 | 14 / 10 / 4 / 5 |
| 用户 / 订单 / 明细 / 调用 | 40 / 100 / 184 / 3000 |
| paid 订单 / 销售额 / Token | 85 / 4228.90 / 92950000 |
| 完整性 / 权限 / 综合验收 | C01～C14 / R01～R17 / VFY01～VFY14 全部 PASS |
| 注册前订单 / 注册前调用 / 到期后消费 / 历史负余额 | 0 / 0 / 0 / 0 |
| 两库业务内容签名 | 14 表一致 |
| 证据 | 22 组 SQL 与日志，26 张分页输出控件截图 |

Q01～Q12 成功执行，经营结果与独立验收对账。Q06 可用低库存账号为 0；库存视图纯额度低于阈值的账号为 2。两者筛选不同。Q11 最近 14 天与全周期月汇总是不同窗口，完整日/月汇总才用于总量对账。Q12 当前最高消耗账号为 8，旧账号 7 的结果属于修复前版本。

## 三、实验总结

当前成果覆盖任务书要求的查询、视图、完整性、角色授权、结果证据和从空库复现。此次修复补充了“最终总量一致”之外的时间与过程验证，也证明权限缺项、直接用户授权和错误样例会被实际验收拒绝。

当前局限包括：样例是合成数据；库存状态为固定历史快照；WITHOUT LOGIN 用户用于课程演示；跨表规则通过验收检测，后续真实事务必须在存储过程或相应事务逻辑中即时维护。第一周会员下单、支付、修改资料以及店员退款职责在本阶段尚未完整实现，不以开放任意基表写权限代替这些工作。

第二名成员独立复现尚未登记，自动化多库验证不等于团队独立复核。

## 四、证据位置

- [SQL 入口](../sql/README.md)、[复现说明](../docs/reproduction.md)
- [原始任务书与要求映射](../docs/requirements/README.md)
- [执行日志与截图](../result/README.md)、[截图索引](../result/screenshots/README.md)
- [角色流程与权限矩阵](role_workflow.md)
- [AI 日志](../docs/ai_usage_log.md)、[组内分工](../docs/team_division.md)
- [各周历史材料](../archive/README.md)
