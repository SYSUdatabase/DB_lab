# AI使用记录

## 使用场景
- 提示词："我现在在设计API Token中转站的项目，告诉我其中可能存在的业务流程，角色与职能清单，数据边界清单供我选择"

## AI协助内容与人工修改

### 1. 业务流程梳理
**AI输出**：AI提供了通用的电商业务流程模板，包括用户注册、浏览商品、下单、支付、发货等环节。
**人工修改**：根据"API Token中转站"的特点，将"发货"环节改为"Token充值到账户"，并增加了"使用Token"和"余额管理"环节。删除了与虚拟商品无关的物流环节。

### 2. 角色与职能清单
**AI输出**：AI建议设置管理员、客服、用户三种角色，并列出了常见职能。
**人工修改**：我们考虑到还有未注测的用户，增加了"游客"角色，细化了各角色的权限范围，特别是店员不能修改商品价格和删除数据的限制。

### 3. 数据边界划定
**AI输出**：AI列出了电商系统常见的数据存储项，包括用户信息、商品信息、订单信息等。
**人工修改**：根据课程要求，明确增加了"Token余额"和"Token使用记录"两个核心实体。同时，去除了"物流信息"、"商品图片"等非必要字段，简化设计。同时考虑到 API 调用涉及客户隐私与商业机密，我们进一步将"API 调用的原始请求与响应内容"明确列入不进库清单，数据库中仅保留按订单/周期汇总的消耗量，原始调用内容不落库。

### 4. 核心实体关系
**AI输出**：AI提供了基本的ER图关系建议。
**人工修改**：明确了"一个用户可以有多个Token余额记录（按AI模型区分）"这一特殊关系，这是API Token中转站的业务特点。

## 验证与确认
所有AI输出内容均经过小组讨论和修改，确保符合课程要求和实际业务场景。其中，API 调用原始内容的保密处理由小组结合业务安全需求讨论确定，最终文档已由阮依成整合并确认。

## 工具版本
- AI模型：GPT-4
- 使用时间：2026年9月10日

---

## 第二周AI使用记录

### 使用场景
- 提示词："请帮我设计一个API Token中转站的数据库表结构，包括用户、商品、库存、订单、订单明细、员工、Token余额、Token使用记录、角色表，要求定义字段、类型、约束、主外键，并给出样例数据。"

### AI协助内容与人工修改

#### 1. 表结构设计
**AI输出**：AI生成了9张表的完整DDL语句，包括字段类型、约束、主外键。
**人工修改**：
- 调整了字段类型：将`price`从`FLOAT`改为`DECIMAL(10,2)`确保精度。
- 增加了`model_provider`字段到商品表，用于区分不同AI模型。
- 修改了`permissions`字段从`VARCHAR`改为`TEXT`存储JSON，便于扩展。
- 统一了时间字段命名：`created_at`、`updated_at`、`used_at`等。

#### 2. 约束设计
**AI输出**：AI建议了主键、外键、唯一约束。
**人工修改**：
- 为`Users`表的`username`和`email`添加了唯一约束。
- 为`Inventory`表的`product_id`添加了唯一约束（每个商品一条库存记录）。
- 为`TokenBalances`表的`user_id + model_provider`添加了复合唯一约束。
- 为`OrderDetails`表的`order_id + product_id`添加了复合唯一约束。

#### 3. 样例数据
**AI输出**：AI生成了示例INSERT语句。
**人工修改**：
- 调整了样例数据使其更符合业务场景（如Token数量、价格）。
- 确保外键引用正确（如`product_id`对应商品表）。
- 添加了状态字段的枚举值（如`active`、`frozen`）。

#### 4. 关系图补充
**AI输出**：AI提供了基本的表关系描述。
**人工修改**：补充了"Token余额按用户+模型区分"的特殊关系，这是API Token中转站的业务特点。

### 验证与确认
所有表结构经过小组讨论，确保覆盖第一周定义的所有进库实体。样例数据能够支持后续的CRUD操作演示。最终设计已由阮依成整合并确认。

---

## 第二周AI使用记录 v2

### 使用场景
- 提示词："根据反馈意见，我的API Token中转站数据库设计需要修改：1. 加UpstreamAccount表；2. Inventory改为关联UpstreamAccount；3. 加InventoryLog、RestockTask、ExceptionLog、UsageSummary表；4. Products的name设为UNIQUE；5. 更新样例数据密码哈希格式。请帮我重新设计表结构。"

### AI协助内容与人工修改

#### 1. 上游账号表设计
**AI输出**：AI生成了UpstreamAccount表结构，包含提供商、账号名称、API密钥、总采购额度、已用额度等字段。
**人工修改**：
- 增加了`available_quota`计算字段（total_quota - used_quota），便于查询。
- 增加了`safety_threshold`字段，用于触发补货提醒。
- 增加了`expires_at`字段，记录账号过期时间。
- 将`api_key`字段说明为加密存储，确保安全。

#### 2. 库存表重构
**AI输出**：AI建议将Inventory表关联到UpstreamAccount。
**人工修改**：
- 将`stock_quantity`改为`current_quota`，语义更准确。
- 增加了`last_updated_at`字段。
- 确保每个上游账号只有一条库存记录（唯一约束）。

#### 3. 新增表设计
**AI输出**：AI生成了InventoryLog、RestockTask、ExceptionLog、UsageSummary四张表。
**人工修改**：
- **InventoryLog**：增加了`reference_type`字段，区分关联的是订单还是补货任务。
- **RestockTask**：增加了`actual_amount`字段，记录实际补货数量；增加了`notes`字段。
- **ExceptionLog**：增加了`stack_trace`字段，便于调试；增加了处理流程字段。
- **UsageSummary**：增加了`request_count`字段，统计API调用次数。

#### 4. 商品表调整
**AI输出**：AI建议将Products.name设为UNIQUE。
**人工修改**：
- 除了`name` UNIQUE外，还增加了`(model_provider, token_amount)`作为复合唯一约束。
- 增加了`required_upstream_tokens`字段，明确每个商品消耗的上游Token数量。

#### 5. 样例数据更新
**AI输出**：AI生成了新的样例数据。
**人工修改**：
- 将密码哈希改为更真实的bcrypt格式（60字符）。
- 为上游账号设置了合理的额度数据。
- 确保所有外键引用正确。
- 为库存流水、补货任务、异常记录添加了示例数据。

### 验证与确认
修订后的设计完全解决了反馈中的8个问题：
1. Token消耗扣减号池库存（通过UpstreamAccount关联）
2. Products和Inventory关系清晰（Inventory关联UpstreamAccount）
3. TokenUsageLogs数据量问题（增加UsageSummary汇总表）
4. Roles表和数据库角色权限分离（说明应用层与数据库层区别）
5. 补货相关表（RestockTask）
6. 异常记录表（ExceptionLog）
7. 密码哈希格式（bcrypt 60字符）
8. Products候选码（name UNIQUE + 复合唯一约束）

最终设计已由阮依成整合并确认。

---

## 人工指导AI记录

### 指导时间
2026年9月16日

### 指导内容
人工提供反馈意见，指出第二周设计中的8个问题，并给出了具体的修改建议。

### 反馈问题清单
1. **Token消耗没有扣减号池库存**：Inventory.stock_quantity只是一个数字，没有和具体上游账号关联。
2. **Products和Inventory的关系不清晰**：Inventory应该关联的是上游账号，而不是套餐。
3. **TokenUsageLogs逐次记录，数据量会爆炸**：需要按周期汇总的消耗量，不是逐次记录。
4. **Roles表和数据库角色权限的关系没理清**：课程要求的是SQL Server的数据库角色，不是自己建的角色表。
5. **缺少补货相关表**：没有补货任务表，第三阶段做补货事务时没有对象。
6. **缺少异常记录表**：第一周数据边界里提到了"异常记录进库"，但第二周没有对应表。
7. **密码哈希字段长度**：样例数据里的bcrypt哈希不是真实格式。
8. **Products的候选码**：name本身应该唯一。

### 人工指导AI的具体建议
**问题1建议**：
- 加一张UpstreamAccount表（上游账号：账号ID、平台、总采购额度、安全阈值、状态）
- Inventory改为关联UpstreamAccount，记录每个上游账号的当前可用额度
- 加一张InventoryLog（库存流水：账号ID、变动类型、变动量、关联订单、时间）

**问题2建议**：
- Inventory应该关联的是上游账号，而不是套餐
- 库存本质是上游账号的可用额度，不是"套餐还能卖几份"

**问题3建议**：
- 保留TokenUsageLogs作为原始日志（可以不入库，或者只存最近N天）
- 加一张UsageSummary（汇总表：用户ID、套餐ID、周期、消耗量）
- 预测基于UsageSummary，不基于TokenUsageLogs

**问题4建议**：
- Roles表可以保留，用于应用层的权限描述
- 数据库层的权限用SQL Server的CREATE ROLE + GRANT实现
- 两者不要混为一谈

**问题5建议**：
- 加RestockTask（补货任务：任务ID、账号ID、触发原因、补货方式、数量、创建人、执行人、状态、时间）

**问题6建议**：
- 加ExceptionLog（异常ID、类型、关联ID、处理人、处理结果、时间）

**问题7建议**：
- bcrypt哈希通常是$2b$12$开头，后面跟53个字符，总共60个字符
- 样例数据改成真实格式

**问题8建议**：
- name设为UNIQUE
- 或者(model_provider, token_amount)设为UNIQUE

### AI执行情况
根据人工指导，AI完成了以下修改：
1. 新增UpstreamAccount表
2. 重构Inventory表关联UpstreamAccount
3. 新增InventoryLog表
4. 新增RestockTask表
5. 新增ExceptionLog表
6. 新增UsageSummary表
7. 修改Products表name为UNIQUE
8. 更新样例数据密码哈希格式

### 指导效果
通过人工指导AI，数据库设计从9张表扩展到14张表，完全解决了所有反馈问题，为后续阶段（补货事务、并发控制、预测分析）奠定了坚实基础。

---

## 第三轮人工指导AI记录

### 指导时间
2026年9月16日（第二轮反馈后）

### 指导内容
人工提供第三轮反馈，指出6个小问题。

### 反馈问题清单
1. **available_quota计算字段冗余**：建议删掉，保留total_quota + used_quota + Inventory.current_quota
2. **api_key字段样例数据是明文**：应改为占位符，说明加密存储
3. **Orders和OrderDetails的Token字段重复**：需要在设计说明中说明冗余合理性
4. **UsageSummary候选码不完整**：需要加上period_end
5. **ExceptionLog.stack_trace字段不该入库**：建议删掉或改error_detail
6. **Roles.permissions类型**：改NVARCHAR(MAX) + ISJSON约束

### AI执行情况
根据第三轮人工指导，AI完成了以下修改：
1. 删除UpstreamAccount.available_quota字段
2. 修改api_key样例数据为占位符，说明加密存储
3. 在设计说明中补充Orders.total_tokens = SUM(OrderDetails.total_tokens)
4. 修改UsageSummary候选码加上period_end
5. 将ExceptionLog.stack_trace改为error_detail
6. 修改Roles.permissions类型为NVARCHAR(MAX) + ISJSON约束
7. 在设计说明中补充"库存三层语义""Token换算""补货两种方式"

### 指导效果
通过第三轮人工指导，数据库设计更加精确，为后续阶段做好了充分准备。