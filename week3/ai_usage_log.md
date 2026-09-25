# 第三周 AI 使用记录

## 使用时间
2026年9月23日

## 使用场景
- 提示词：根据课程第三周任务书、第二周数据字典和 `week3_plan.md`，将 API Token 中转站的 14 张表落地到 SQL Server，生成可复现样例数据、CRUD 演示并验证从空库重放。

## AI 协助内容

### 1. DDL 实现
AI根据第二周的 14 张表设计生成 SQL Server DDL 候选实现，包括主键、候选码、外键、非空、默认值和 CHECK 约束，并按依赖关系安排建表顺序。

### 2. 实现级修正落地
按照 `week3_plan.md` 已记录的人工决策，实际脚本采用：
- `TEXT` 改为 `NVARCHAR(MAX)`；
- 中文业务文本优先使用 `NVARCHAR`；
- 时间戳改为 `DATETIME2(0)`；
- bcrypt 形教学占位符严格保持 60 字符；
- 状态枚举和数值域落地为 CHECK；
- 样例主键使用显式 ID，保证外键稳定和重放一致；
- API Key 仅使用 `DEMO_NOT_A_REAL_API_KEY_*` 占位符，不使用真实密钥。

### 3. 合成数据生成器
AI协助编写 `tools/datagen.py`，使用固定随机种子 `20260923` 生成用户、商品、订单、Token 使用、库存流水、补货和异常等关联数据。

生成器加入一致性自检：
- 订单汇总等于订单明细之和；
- 用户余额和库存均非负；
- 库存当前值等于总采购额度减累计使用量；
- 库存当前值等于库存流水净额；
- 关键外键均命中；
- 所有 API Key 均为教学占位符。

### 4. CRUD 演示
AI协助生成 `03_crud_demo.sql`，分别对 Products、Inventory、Orders 展示新增、查询、修改和删除，并在操作前后查询目标记录。演示操作置于事务中，完成后回滚，不污染基础样例数据。

### 5. 验证与复现
实际在 `localhost\SQLEXPRESS` 执行：
`00_create_database.sql → 01_create_tables.sql → 02_insert_data.sql → 03_crud_demo.sql`。

验证结果：
- 14 张用户表创建成功；
- 订单汇总不一致数为 0；
- 库存与库存流水不一致数为 0；
- 负价格 CHECK 测试通过；
- Orders.user_id 非法外键测试通过；
- 删除本周新建实验库后重新执行全部脚本，关键数据签名与首次完全一致。

## 数据量
- Users：40
- Products：10
- UpstreamAccount：8
- Inventory：8
- Employees：6
- Orders：100
- OrderDetails：184
- InventoryLog：3012
- TokenBalances：61
- TokenUsageLogs：3000
- UsageSummary：3394
- RestockTask：8
- ExceptionLog：15

## 定价资料核对
按 `week3_plan.md` 要求，商品价格方向在实现时参考了 2026-09-23 的 OpenAI、Anthropic 和 Google 官方 API 定价页面。数据库中的零售套餐价格经过简化，仅用于课程实验，不作为真实报价。

## 工具与人工复核说明
- AI模型：GPT-5.6 Sol
- Python：3.12.6
- Python 语法编译检查：通过
- 数据生成器自检：PASS
- ruff：本机未安装，因此未额外安装或执行 ruff 格式化
- SQL 脚本已通过实际 SQL Server 执行结果复核，不仅停留在文本生成阶段
