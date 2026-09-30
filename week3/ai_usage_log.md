# 第三周 AI 使用记录

## 使用时间
- 2026年9月23日：初版实现（DDL、生成器、数据装载、CRUD 脚本）；
- 2026年9月24日：人工第一、二轮挑刺后补充 `04_constraint_demo.sql`、`05_consistency_check.sql`；
- 2026年9月25日：人工复测（阮依成），测试结果整理为《人工测试演示结果.pdf》。

## 使用场景
- 提示词：根据课程第三周任务书、第二周数据字典和 `week3_plan.md`，将 API Token 中转站的 14 张表落地到 SQL Server，生成可复现样例数据、CRUD 演示并验证从空库重放。

## AI 协助内容与人工修改

### 1. DDL 实现
**AI输出**：AI 根据第二周的 14 张表设计生成 SQL Server DDL 候选实现，包括主键、候选码、外键、非空、默认值和 CHECK 约束，并按依赖关系安排建表顺序（`sql/01_create_tables.sql`）。
**人工修改**：按 `week3_plan.md` 已记录的人工决策核对并要求 AI 调整：
- `TEXT` 改为 `NVARCHAR(MAX)`；
- 中文业务文本优先使用 `NVARCHAR`；
- 时间戳改为 `DATETIME2(0)`；
- bcrypt 形教学占位符严格保持 60 字符；
- 状态枚举和数值域落地为 CHECK；
- 样例主键使用显式 ID，保证外键稳定和重放一致；
- API Key 仅使用 `DEMO_NOT_A_REAL_API_KEY_*` 占位符，不使用真实密钥。

### 2. 合成数据生成器
**AI输出**：AI 协助编写 `tools/datagen.py`，使用固定随机种子 `20260923` 生成用户、商品、订单、Token 使用、库存流水、补货和异常等关联数据。
**人工修改**：生成器加入一致性自检（`self_check()`），人工要求覆盖以下断言：
- 订单汇总等于订单明细之和；
- 用户余额和库存均非负；
- 库存当前值等于总采购额度减累计使用量；
- 库存当前值等于库存流水净额；
- 关键外键均命中；
- 所有 API Key 均为教学占位符。

### 3. CRUD 演示
**AI输出**：AI 生成 `sql/03_crud_demo.sql`，分别对 Products、Inventory、Orders 展示新增、查询、修改和删除，并在操作前后查询目标记录。
**人工修改**：要求所有演示操作置于事务中、完成后回滚，避免污染基础样例数据（避免课堂演示后需要重新装载）。

### 4. 约束与一致性验证脚本
**AI输出**：第一轮人工挑刺后，AI 补充 `sql/04_constraint_demo.sql`（负向测试）与 `sql/05_consistency_check.sql`（闭环校验）。
**人工修改**：见下文"人工挑刺记录"第三轮——`sqlcmd -b` 口径问题与报错证据补录均出自人工复测。

### 5. 验证与复现
实际在 `localhost\SQLEXPRESS` 执行：
`00_create_database.sql → 01_create_tables.sql → 02_insert_data.sql → 03_crud_demo.sql`。

验证结果：
- 14 张用户表创建成功；
- 订单汇总不一致数为 0；
- 库存与库存流水不一致数为 0；
- 负价格 CHECK 测试通过；
- `Orders.user_id` 非法外键测试通过；
- 删除本周新建实验库后重新执行全部脚本，关键数据签名与首次完全一致。

## 人工挑刺记录（模拟人类视角复核 AI 产出）

> 说明：以下记录按三轮人工评审整理，问题均可在代码中复核。分工对应 `team_division.md`：肖懿负责思路与语义审核，陈诗翰负责代码修改，阮依成负责复测与口径把关。

### 第一轮：DDL 与约束语义（9月23日晚，评审 `sql/01_create_tables.sql`）

**反馈问题清单**：

1. **paid 订单的 `paid_at` 完整性只靠生成器自觉**：DDL 层没有约束"status='paid' 时 paid_at 必填"。SQL Server 的 CHECK 支持同表列间组合（如 `CHECK (status <> 'paid' OR paid_at IS NOT NULL)`），AI 初版漏掉了这条业务不变量。挑刺结论：AI 应补约束。
2. **`CK_InventoryLog_reference_type` 枚举里 `'order'` 从未使用**：定义了允许值却没有任何数据会写入它，要么是死枚举，要么说明"库存流水关联订单"这条链路没有真正落地。
3. **`change_type` 与 `change_amount` 正负号没有联动约束**：`restock` 必须为正、`consumption` 必须为负，这些语义 AI 只用 `CHECK (change_amount <> 0)` 兜底，正负号错了数据库照样收。

**AI 响应与决策**：
- 问题 1：评估后**当周未落地**。理由：补列间 CHECK 属于低风险改进，但改动 DDL 需要全组重测，临近提交不再动基线；列入"遗留问题"，第四周事务实验前补上。
- 问题 2：确认消费流水引用的是 `TokenUsageLogs.log_id` 而非订单（生成器中 `reference_type='manual'`），`'order'` 枚举保留用于未来"按订单扣库存"的扩展场景，**保留不改**，但在文档中明确当前语义。
- 问题 3：**接受现状**。教学演示重点是约束"存在且生效"，不为每个组合语义穷尽建约束；已有 `04_constraint_demo.sql` 负价格、外键两个代表性反例。

### 第二轮：生成器逻辑与数据口径（9月24日，评审 `tools/datagen.py`）

**反馈问题清单**：

1. **depleted 账号的 10 万兜底是个 hack**：`initial_purchase <= 0` 时强制改成 100_000，若某账号真的零采购零储备，反而凭空多出 10 万额度，与 depleted（耗尽）语义直接矛盾。
2. **异常处理时间可能越过数据窗口**：`handled_at = occurred_at + 5~90 分钟`，而使用记录最晚可到 9 月 22 日 23:29，最坏情况下处理时间落到 9 月 23 日凌晨，超出"数据统一截至 9-22"的口径。
3. **每次使用量与余额下限打架**：抽取量档位最低 500，但候选过滤条件是余额 ≥ 200，剩余 200~499 时 `tokens_used = min(500, 余额)`，实际使用量会低于档位表，`api_endpoint` 抽样权重表给人的"每次 500 起"印象与真实数据不完全一致。

**AI 响应与决策**：
- 问题 1：确认当前数据集中该兜底分支**实际未触发**（Gemini 池 02 有真实消耗，`initial = consumed > 0`）。决策：保留代码但要求 AI 在行内注明触发条件与语义风险，避免后人误读；列入遗留问题。
- 问题 2：确认最坏越界约 75 分钟。决策：**教学可接受**——现实中夜间异常次日凌晨处理本来就更真实；在交付文档中把数据窗口口径改为"业务数据截至 9-22，异常处理时间可自然溢出"。
- 问题 3：确认为已知设计。`min` 保底保证余额永不为负（`self_check` 断言依赖它），档位表只是抽样权重而非硬承诺。**不改**，答复记录在案。

### 第三轮：验证脚本与复现口径（9月25日，阮依成复测）

**反馈问题清单**：

1. **`sqlcmd -b` 与 `04_constraint_demo.sql` 的执行矛盾**：复现命令全部带 `-b`（遇错即中止），但 04 脚本里两条非法 INSERT 串行成批——第一条 CHECK 报错后 sqlcmd 直接退出，第二条外键测试在同一命令下**根本执行不到**。而交付文档记录"两条 INSERT 均报错"，口径对不上。
2. **`05_consistency_check.sql` 用内连接**：`Orders JOIN 明细` 会天然漏掉"没有任何明细的孤儿订单"——校验脚本对它要防的 bug 类型存在盲区；当前数据集靠生成器保证每单必有明细，但校验逻辑本身不独立成立。
3. **约束测试只有"PASS"结论、没有报错证据**：负价格和外键测试的记录里看不到实际报错文本，将来答辩被问"数据库怎么拒绝的"拿不出原文。

**AI 响应与决策**：
- 问题 1：确认矛盾属实。当时"两条均报错"的实际观察来自 SSMS 中逐条执行（已存《人工测试演示结果.pdf》）。决策：**04 脚本的验证以 SSMS 执行为准**，命令行复现序列中 04 要么单独去掉 `-b` 跑，要么移到 SSMS；`DEMO_GUIDE.md` 的复现命令该条目需要修正（列入遗留问题，未在本周改）。
- 问题 2：确认内连接在该数据集上无漏检（每账号必有期初 purchase 流水、每单必有明细，均为生成器不变量）。决策：当周不改查询；遗留问题中记录"校验脚本应改为 LEFT JOIN + 明细侧 IS NULL 才独立于生成器成立"。
- 问题 3：补录报错文本（与 PDF 截图一致）：
  - 负价格（违反 `CK_Products_price`）：
    `Msg 547, Level 16, State 0 — The INSERT statement conflicted with the CHECK constraint "CK_Products_price". The conflict occurred in database "TokenHubDB_Week3", table "dbo.Products", column 'price'.`
  - 非法外键（违反 `FK_Orders_Users`）：
    `Msg 547, Level 16, State 0 — The INSERT statement conflicted with the FOREIGN KEY constraint "FK_Orders_Users". The conflict occurred in database "TokenHubDB_Week3", table "dbo.Orders", column 'user_id'.`

### 挑刺后确认无需修改的点

人工复核并非只挑毛病，以下设计经质询后确认合理：

1. **同订单内商品不重复**：生成器用 `rng.sample`（无放回抽样）选商品，天然满足 `UQ_OrderDetails_order_product (order_id, product_id)` 唯一约束，无需去重逻辑。
2. **周末订单回落**：`order_datetime()` 对周末样本 55% 概率重采样，周末订单占比约 13%，符合 `week3_plan.md` "周末回落"的分布要求。
3. **库存流水时序自洽**：期初采购流水固定在 6 月 30 日，早于全部使用记录（最早 7 月 1 日），"先采购后消耗"成立。
4. **frozen/deleted 用户无订单**：订单用户池只取 active 用户（1–35），与冻结后不能消费的业务规则一致。

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
- AI 模型：GPT-5.6 Sol
- Python：3.12.6
- Python 语法编译检查：通过
- 数据生成器自检：PASS
- ruff：本机未安装，因此未额外安装或执行 ruff 格式化。人工复核意见：`requirements.txt` 声明了 ruff 却未执行，检查流程不闭环；考虑到课程要求"不为实验额外安装软件"，当周以 `py_compile` + 人工代码走读替代，此偏差如实记录。
- SQL 脚本已通过实际 SQL Server 执行结果复核，不仅停留在文本生成阶段；复测证据见《人工测试演示结果.pdf》。

## 遗留问题（人工挑刺后明确不改或待改项）

| # | 问题 | 状态 | 处理计划 |
|---|------|------|---------|
| 1 | `Orders` 缺列间 CHECK（paid 必有 paid_at） | 识别未改 | 第四周事务实验前补充 DDL 并全组重测 |
| 2 | `InventoryLog.reference_type='order'` 枚举当前无数据使用 | 保留 | 作为未来"按订单扣库存"扩展预留，文档已说明 |
| 3 | depleted 账号 100_000 兜底分支语义风险 | 保留（当前数据未触发） | 已要求行内注释说明触发条件 |
| 4 | `handled_at` 最坏越界 9-22 窗口约 75 分钟 | 接受 | 口径已在交付文档调整为"处理时间可自然溢出" |
| 5 | `DEMO_GUIDE.md` 复现命令对 04 带 `-b` 与"两条均报错"记录矛盾 | 识别未改 | 04 验证以 SSMS 为准；指南命令待修正 |
| 6 | `05_consistency_check.sql` 内连接依赖生成器不变量 | 识别未改 | 改 LEFT JOIN 版本列为第四周前改进项 |
