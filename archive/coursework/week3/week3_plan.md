# 第三周任务规划（DDL 与数据修改）

> 状态：规划中（本文档先于实现编写，作为小组分工与实施依据；执行完成后产出 `week3_deliverables.md` 回填结果）
> 依据：课程第三周任务书（ch3 DDL 与数据修改）+ 第二周关系模式设计（`week2_deliverables_v2.md`）

## 1. 任务解读

本周目标一句话：**把第二周纸面上的 14 张表，在 SQL Server 里从空库开始变成一个可复现、有数据、可增删改查的数据库。**

课程任务书五项任务 → 我们的工作分解：

| # | 任务书要求 | 我们的产出 |
|---|-----------|-----------|
| 1 | 创建数据库与数据表 | 建库脚本（排序规则决策）+ 14 张表 DDL |
| 2 | 定义表结构（类型、约束） | 主键/候选码/外键/非空/默认值/CHECK 全部落地为 SQL 约束 |
| 3 | 添加样例数据 | 数据生成器产出 INSERT 脚本（量级远超第二周的每表 2-3 条） |
| 4 | 完成增删改查 | CRUD 演示脚本，覆盖商品、库存、订单三类对象 |
| 5 | 验证脚本可复现 | sqlcmd 从空库重放全部脚本 + 一致性校验查询 |

## 2. 交付物与文件组织

```
DB_lab/
├── sql/
│   ├── 00_create_database.sql    # 建库（含排序规则）
│   ├── 01_create_tables.sql      # 14 张表 DDL + 全部约束（按依赖顺序）
│   ├── 02_insert_data.sql        # 样例数据（生成器产出，显式 ID）
│   └── 03_crud_demo.sql          # CRUD 演示（每个写操作前后都有 SELECT）
├── tools/
│   └── datagen.py                # 合成数据生成器（固定随机种子）
└── week3_deliverables.md         # 最终交付文档（脚本说明 + 执行结果 + 复现步骤）
```

脚本按编号即执行顺序；复现说明写在交付文档中（课程要求"写明脚本执行顺序和从空数据库开始运行的方法"）。

## 3. 对第二周设计的实现级修正（建表前必须处理）

> 以下问题在把数据字典翻译成 SQL Server DDL 时逐一核对发现。**这是本周最重要的一批决策**，修正理由均已记录，将同步更新 `ai_usage_log.md`。

| # | 问题 | 修正方案 | 理由 |
|---|------|---------|------|
| 1 | `description`/`error_message`/`notes` 等字段定义为 `TEXT` | 改为 `NVARCHAR(MAX)` | SQL Server 的 `TEXT`/`NTEXT` 自 2005 起已废弃，将来的版本会移除；微软官方推荐用 `NVARCHAR(MAX)` 替代 |
| 2 | 员工姓名（张经理）、账号名（主账号-001）、备注/原因等中文字段定义为 `VARCHAR` | 可能含中文的字段改 `NVARCHAR`；纯 ASCII 域（status 枚举、username、email、model_provider 等）保持 `VARCHAR` | 实例默认排序规则为 `Latin1_General_CI_AS` 时 `VARCHAR` 存中文会变问号；`NVARCHAR`（UTF-16）不受排序规则影响 |
| 3 | `password_hash` 样例值为 69 字符，超 `VARCHAR(60)` | 生成器产出严格 60 字符的 bcrypt 形占位符（`$2b$12$` + 53 位） | bcrypt 哈希恒为 60 字符；第二周手写样例插入会报 "string or binary data would be truncated" |
| 4 | 样例元组依赖隐式自增 ID | 建表用 `IDENTITY(1,1)`，数据脚本 `SET IDENTITY_INSERT <table> ON` 显式插入固定 ID | 外键引用 ID 稳定 + 重放结果完全一致（课程要求"得到相同的表结构和样例数据"） |
| 5 | 默认值 `GETDATE()` 影响可复现性 | 样例数据全部显式写时间戳列；`GETDATE()` 默认值仅作为业务兜底保留 | 默认值只在"未显式提供"时生效；数据脚本显式提供后，重放结果与首跑一致 |
| 6 | `DATETIME` 精度低（3.33ms、无小数秒） | 时间戳字段统一 `DATETIME2(0)` | `DATETIME2` 是微软推荐的现代类型；实验数据精确到秒已足够 |
| 7 | 枚举域（status 等）仅写在文档里 | 全部落成 `CHECK` 约束（含 `Roles.permissions` 的 `ISJSON()` 检查，第二周已约定） | 课程第 4 周要演示"非法数据被拒绝"，本周先把约束建好正好衔接 |

建表顺序（先被引用、后引用，删除时反向）：
`Roles → Users → Products → UpstreamAccount → Inventory → Employees → Orders → OrderDetails → InventoryLog → TokenBalances → TokenUsageLogs → UsageSummary → RestockTask → ExceptionLog`

## 4. 样例数据从哪来（核心决策）

### 4.1 结论先行

**这个场景不存在可以"找"到的现成数据。** 可行的路径是写一个合成数据生成器，用"真实锚点 + 合理分布 + 业务闭环一致性"让数据可信。理由：

1. 上游账号库存、API Key、补货流水是**商业敏感数据**，现实中不可能有公开数据集；
2. 公开电商数据集（Kaggle 上的 Olist、Superstore 等）卖的是实物商品，没有"上游账号/号池库存/Token 换算"这条业务线，字段映射改造成本高，改完既不真实也不可控；
3. 课程的验收标准是"数据体现业务联系、量够支撑后续实验、脚本可复现"——这三条合成数据都能精确满足，真实数据反而做不到最后一条。

### 4.2 备选方案对比

| 方案 | 数量可控 | 外键一致性 | 可复现 | 真实感 | 结论 |
|------|---------|-----------|--------|--------|------|
| 手工扩写 INSERT | 差（易错） | 靠人肉 | 是 | 低 | 仅保留第二周样例作冒烟测试 |
| 公开数据集改造 | 是 | 差（需大改） | 是 | 中（错业务） | 否决：业务线不匹配 |
| **脚本合成（推荐）** | 是 | 生成逻辑保证 | 固定种子 | 高（见 4.3） | **采用** |

### 4.3 让合成数据"像真的"的四个手段

1. **真实锚点**：商品定价参考各模型公开 API 定价（GPT/Claude/Gemini 每百万 token 单价），叠加 1.2–1.5 倍中转加价，`required_upstream_tokens` 即由加价率导出（呼应第二周"卖 100K 耗上游 120K"的损耗设计）。具体单价在建表时查官网定价页核实，不凭记忆写。
2. **合理分布**：
   - 用户活跃度幂律（少数重度用户贡献大多数用量，80/20）；
   - 订单时间聚集在工作日 9–11 / 14–17 / 20–23 点，周末回落；
   - 单笔订单商品数 1–3、数量以 1 为主（偶尔囤货 2–3）。
3. **业务闭环一致性**（这是"体现业务联系"的硬要求，全部由生成器保证而非手填）：
   - `Orders.total_tokens/total_amount = SUM(OrderDetails)`（第二周关键约束）；
   - paid 订单 → `TokenBalances` 入账 → `TokenUsageLogs` 按次扣减（余额扣至 0 的用户自然停用）；
   - 每次 Token 消耗 → 对应上游账号 `Inventory` 扣减 + 一条 `InventoryLog` 负流水；
   - 库存跌破 `safety_threshold` → 生成一条 `RestockTask`（部分 completed 带回补正流水，部分 pending）；
   - 按 1–2% 概率注入 API 异常 → `ExceptionLog`（大部分 resolved，个别 escalated）；
   - `UsageSummary` 直接从 `TokenUsageLogs` 聚合得出，而不是独立随机造。
4. **固定随机种子**：同一份 `datagen.py` 任何机器跑出完全相同的 `02_insert_data.sql`。

### 4.4 数据量规划

时间跨度约 12 周（2026-07-01 ~ 2026-09-22），足够第 4 周视图统计和第四阶段预测。

| 表 | 行数 | 说明 |
|----|------|------|
| Users | ~40 | active 35 / frozen 4 / deleted 1 |
| Products | ~10 | OpenAI 4 / Claude 3 / Gemini 3，多档套餐 |
| UpstreamAccount | ~8 | 含 depleted/expired/suspended 各 1，支撑补货与异常故事线 |
| Inventory / Roles / Employees | 8 / 3 / 6 | 1:1 或固定 |
| Orders | ~100 | paid 85 / pending 8 / cancelled 5 / refunded 2 |
| OrderDetails | ~180 | |
| TokenBalances | ~100 | 用户 × provider 有效组合 |
| TokenUsageLogs | ~3000 | 主要数据量 |
| InventoryLog | ~3200 | 采购 + 消耗 + 补货 |
| UsageSummary | ~3000-5000 | daily/weekly/monthly 三粒度聚合 |
| RestockTask | ~8 | 对应低库存事件 |
| ExceptionLog | ~15 | |

### 4.5 生成器实现要求

- Python 3.11+ + venv，仅标准库（`random`/`datetime`/`dataclasses`），不引第三方依赖；
- 完整 type hints，`ruff` 格式化（全局规范）；
- 结构：`造静态实体 → 造订单时间线 → 余额/用量扣减 → 库存/补货/异常 → 聚合汇总 → 一致性自检 → 渲染 SQL`；
- **一致性自检**必须做：订单汇总=明细和、余额/库存非负、`Inventory.current_quota == total_quota - Σ流水`、外键全部命中；自检失败直接报错退出，不静默放行；
- 输出显式 ID + `IDENTITY_INSERT` 包裹的 `02_insert_data.sql`。

## 5. 实施步骤与分工建议

| 步骤 | 内容 | 验证方式 | 建议分工 |
|------|------|---------|---------|
| S1 | `00/01` 建库建表 DDL（含第 3 节全部修正） | SSMS 执行无错 + 约束冒烟（插非法数据应被拒） | 阮依成 |
| S2 | `datagen.py` 生成器 + 自检 | 自检全绿 + 生成 SQL 行数符合 4.4 | 肖懿 |
| S3 | `02_insert_data.sql` 装载 | 行数核对 + 抽查业务闭环查询 | 肖懿 |
| S4 | `03_crud_demo.sql`（写操作前先 SELECT 同条件确认目标行——任务书提示项） | 前后对照结果截图 | 陈诗翰 |
| S5 | 复现验证：drop 后 sqlcmd 从空库按序重放 | 结果与首跑一致（行数/抽查） | 阮依成 |
| S6 | `week3_deliverables.md` 汇总 + `ai_usage_log.md` 补记 AI 协助与人工修改 | — | 阮依成 |

## 6. 环境前置与风险

- **前置**：SQL Server 2025 Express + SSMS 可用（待全组确认；未装则先装，Express 免费）。复现验证优先用 `sqlcmd`（`sqlcmd -S localhost\SQLEXPRESS -E -i sql/00_create_database.sql ...`），比 SSMS 手点更适合演示"从空库重放"。
- **风险 1**：排序规则。若实例为中文排序规则，`VARCHAR` 中文也能存，但我们的方案（第 3 节 #2）不依赖实例配置，移植到任何实例都成立。
- **风险 2**：第 4 周将演示"越权操作失败"，本周建表时先不用急着做数据库层 ROLE/GRANT（那是第 4 周任务），`Roles` 表数据先就位即可。
- **合规**：任务书明确"AI 协助生成候选 SQL，必须逐句检查并记录人工修改"——第 3 节的修正表就是本次人工核对的证据，随交付文档归档。

## 7. 待小组确认的开放问题

1. 数据量按 4.4 的规模是否认可（第 4 周连接/统计、第四阶段预测以此为底）？
2. 商品定价锚点：直接采用"官网单价 × 加价率"，还是组内自定一套整数价格（演示更整洁）？倾向前者。
3. `03_crud_demo.sql` 演示数据是否允许修改 `02` 装载的既有数据（推荐：CRUD 脚本开头先把相关表恢复到装载后状态的说明写清楚，重放顺序 00→01→02→03）？
