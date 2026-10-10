# 第五周执行计划：从 v0.1 反推 ER 模型

- 状态：**2026-10-10 已执行主要交付；小组业务确认和独立人审待办，详情见第七节**。
- 依据：《第五周任务讲解.docx》（ch6 ER 模型），2026-10-10 只读检查当前仓库。
- 工作机器：`LAPTOP-3H5FCR3B`；仓库：`D:\Desktop\DB\DB_lab`。
- 目标：交付可编辑 ER 源图及清晰导出图、业务规则与映射清单、v0.1 问题清单、设计说明与验证记录；能够现场解释关键实体、主码/候选码、联系基数和参与约束。
- **边界**：第五周只做逆向分析、核对、图表与报告，不改现有 v0.1 数据库结构、不写迁移 SQL、不清库、不覆盖既有结果。第六周再讨论迁移和结构修正。除本次计划文件外，其他写入须在开始执行计划时得到用户明确要求；不自动 commit/push。不得读取或展示任何真实密钥、私钥、CDKey、密码等敏感值。

## 一、已核对的项目基线

1. 正式 DDL 为 `sql/01_create_tables.sql`，后续约束位于 `sql/constraint.sql`；另有 `sql/verify.sql`、`sql/role.sql`、`sql/view.sql` 和查询文件。正式阶段报告 `report/stage_report.md` 已嵌入一个 Mermaid ER 草图，**可作参考但不能直接视为第五周验收完成**。
2. 当前 v0.1 共 **14 张表**，业务为 API Token 套餐购买、订单与明细、按 provider 余额、上游账号额度与库存流水、用量及补货异常。现有目录包括 `report/`、`docs/`、`result/`、`plan/`；旧周次材料位于 `archive/`。
3. 当前实体及可核对的键（这里列的是 DDL 中的 PK、UNIQUE，不代表全部都适合作为业务主标识）：

| 表 | 主码（PK） | 唯一标识/候选码线索 |
|---|---|---|
| Roles | role_id | role_name |
| Users | user_id | username；email |
| Products | product_id | name；(model_provider, token_amount) |
| UpstreamAccount | account_id | (provider, account_name) |
| Inventory | inventory_id | account_id |
| Employees | employee_id | account |
| Orders | order_id | 暂无额外 UNIQUE |
| OrderDetails | detail_id | (order_id, product_id) |
| InventoryLog | log_id | 暂无额外 UNIQUE |
| TokenBalances | balance_id | (user_id, model_provider) |
| TokenUsageLogs | log_id | 暂无额外 UNIQUE |
| UsageSummary | summary_id | (user_id, product_id, period_type, period_start) |
| RestockTask | task_id | 暂无额外 UNIQUE |
| ExceptionLog | exception_id | 暂无额外 UNIQUE |

4. `Roles` 是业务数据表，`hub_manager / hub_staff / hub_customer / hub_guest` 是 SQL Server 数据库角色；不能将二者混为一种 ER 实体。`Products` 表示销售套餐，`Inventory` 表示上游账号剩余额度；**不能凭表名假设商品与库存直接存在 FK**。
5. `report/stage_report.md` 的图中有业务意图陈述；第五周需对照真实 DDL 区分“业务上应当成立”和“现有 PK/UNIQUE/FK/CHECK 真正保证了什么”。此前保存的日志只能证明当时执行，不等同于当前数据库现场状态。

## 二、交付文件布局（执行时创建，不在制定计划时创建）

```text
DB_lab/
├─ plan/week5-er-model-plan.md              # 本计划
├─ week5/
│  ├─ data_dictionary.md                     # 14 表实体、属性、行粒度与 PK/候选码/FK
│  ├─ er_diagram.mmd                         # 统一 Crow's Foot/Mermaid 的可编辑 ER 源图
│  ├─ er_diagram.svg                         # 清晰、可放大导出图
│  ├─ er_diagram.png                         # 如需课件/报告粘贴则导出
│  ├─ business_rules_mapping.md              # 关系两端 min/max、条件、表/FK、实现层次
│  ├─ v01_issues.md                          # 证据、影响、保留项及 week6 改进方向
│  └─ design_validation.md                   # 设计说明、场景对应、核验结果与展示稿
└─ result/week5/                             # 仅在需要时保存只读核验记录/真实截图
```

若图过密，可补充分区放大图（销售/余额/上游库存），但**不能用分区图取代覆盖所有核心实体的总图**。每一张图的术语必须与数据字典一致。执行后再将第五周材料链接加入正式报告/README 和要求映射文档。

## 三、具体实施步骤

### P0｜锁定 v0.1 原貌与需求（先做）
- [ ] 核对 Git 状态、14 张表的 DDL、`constraint.sql` 中后加的约束、`verify.sql` 的跨表验证、已存在的报告 ER 图；优先用仓库文本与既有证据，不读取数据表中的敏感值。
- [ ] 建“设计事实 vs 业务规则 vs 样例现象”三栏记录。样例一对一不能证明业务 1:1；FK 可以阻止无父行的子行，但不能单独要求父行至少有一条子行。
- [ ] 不运行 `tools/run_v01.ps1`、不创建/删除实验库、不更新既有数据。若需连接数据库，仅使用可审计的只读系统目录和脱敏统计查询。

### P1｜整理数据字典和实体标识
- [ ] 为每张表填写业务含义、为何需要独立保存、“一行代表什么”、主要属性、PK、所有 UNIQUE 候选码、复合候选码、FK、可空性、重要 CHECK/DEFAULT。
- [ ] 标出关联/事件/汇总类实体：`OrderDetails`、`InventoryLog`、`TokenUsageLogs`、`UsageSummary`；不要把事件流水误看成普通的 M:N 直连。
- [ ] 对照 `sql/01_create_tables.sql`，检查 `Employees.role_id`、`RestockTask.created_by/assigned_to`、`InventoryLog.operator_id`、`ExceptionLog.handled_by` 的 NULL 规则。
- [ ] 不在图、截图或说明中输出任何凭证值；含敏感信息的字段仅记录用途和访问限制，不读值。

### P2｜整理联系、基数、参与约束与实现方式
- [ ] 逐个 FK 建关系映射：`Users→Orders→OrderDetails←Products`；`UpstreamAccount→Inventory/InventoryLog/RestockTask`；`Users→TokenBalances/TokenUsageLogs/UsageSummary`；`Roles→Employees`；员工处理/指派/操作联系等。
- [ ] 每条关系**两端都填写 min..max**（0..1、1..1、0..*、1..*），并说明限定条件及产生该判断的业务依据。
- [ ] 记录“目前如何保证”：PK/UNIQUE/FK/NOT NULL/CHECK、`verify.sql` 检查、业务代码/人工约定或当前完全缺失；只读验证时也要标明是“真实数据库”还是“静态 DDL”证据。
- [ ] 重点分辨：`Orders` 业务上至少一条 `OrderDetails`，现有 FK **无法强制订单头一定有明细**；`UpstreamAccount→Inventory` 在当前 `UNIQUE(account_id)+NOT NULL FK` 下，库存行必须有账号，但账号可以没有库存行（数据库保证的账号侧是 0..1）。
- [ ] `TokenBalances.model_provider` 目前是枚举值而非指向 provider 实体的 FK；`ExceptionLog.related_table/related_id` 和 `InventoryLog.reference_type/reference_id` 不是指向任意目标表的真实 FK，需用虚线/注释区分逻辑关联与物理 FK。
- [ ] 分析 `Products` 与上游账号的 provider 匹配、`TokenUsageLogs` 记录中的 provider 一致性：哪些依靠 `verify.sql` 或流程约定而非数据库 FK。

### P3｜绘制并核对 ER 图
- [x] 编辑源文件保留 Mermaid ER 关系语法，渲染图使用 `1..1`、`0..1`、`0..*`、`1..*` 文本标注两端基数，不显示符号图例。保留实体、关键属性和 PK/UK/FK。
- [ ] 按 14 张表先绘主图。业务约束与当前数据库约束不同时：以**当前 v0.1 的物理实现为主体**，另用文字注明期望业务约束；不得画成已经强制的关系。
- [ ] 核对每条线的两端是否有实际 FK；无 FK 的逻辑联系用注释表或区分样式，不伪装为物理约束。
- [ ] 将源图 `.mmd` 导出 SVG，检查 100% 缩放与投屏可读性、中文不乱码、线条不遮挡关键字段；必要时另导出 PNG 和局部放大图。保留源图以便二次编辑。

### P4｜形成 v0.1 问题与保留清单
- [ ] 每项使用固定字段：**ID｜问题/现状｜业务证据｜技术证据（文件/约束/查询）｜影响｜保留或拟改｜第六周方向｜待团队确认**。
- [ ] 必查问题 A：`UQ_OrderDetails_order_product` 限制同一订单的同一商品只能有一行；业务可用 `quantity` 表示多件，但任务书提醒不能未经讨论就将“一单同商品仅一行”当作普遍业务公理。核实后决定保留或在第六周设计迁移。
- [ ] 必查问题 B：匿名/散客购买——当前 `Orders.user_id NOT NULL` 且关联 `Users`。若要求“不创建账号的散客”直接下单，现设计不能原样表达；必须说明适用条件和候选方案，不能虚构已有支持。
- [ ] 必查问题 C：订单非空明细、上游账号必有库存、provider 一致性、订单汇总与明细、额度与流水、历史余额，区分约束和 `verify.sql` 的回归校验。
- [ ] 必查问题 D：`RestockTask.created_by NOT NULL` 与“自动产生任务”场景是否冲突；`InventoryLog` / `ExceptionLog` 的弱引用是否影响追溯；`Roles` 业务表与数据库角色覆盖范围是否符合业务。
- [ ] 明确合理保留项，例如独立 `OrderDetails`、金额/Token 下单快照、`UpstreamAccount` 与库存分离、按 provider 的余额、事件流水和汇总表；每项写出业务理由、潜在代价和验证依据。
- [ ] 问题只形成**第六周候选迁移设计**，本周禁止直接 `ALTER TABLE`、`DROP`、回填或改变数据生成器。

### P5｜验证三个核心业务场景
- [ ] **多商品订单**：在 ER 中追踪 `Users → Orders → OrderDetails → Products`，用已有样例/只读 SELECT 或历史证据证实一单多商品；并核对订单总额/Token 汇总与快照关系。
- [ ] **会员或散客购买**：证明会员由 `Orders.user_id` 关联 `Users`；对不建账号的散客明确标记“当前不支持/需业务定义”，只有真实可核验证据才能记录为“已支持”。
- [ ] **库存查询**：追踪 `UpstreamAccount → Inventory` 和 `InventoryLog`，解释库存额度与套餐的区别，演示额度、阈值与流水的查询口径；不要把样例的固定历史快照称为当前实时库存。
- [ ] 结果写到 `design_validation.md`：ER 路径、数据库表/字段、验证 SQL（只读）、预期、实际/历史证据位置、结论及局限。没有运行过的检验写“未执行”，不伪造 PASS。

### P6｜报告、人工复核和提交准备
- [ ] 整理 `design_validation.md`：设计思路、实体独立性、M:N 如何通过 `OrderDetails` 等中间实体实现、参与约束、合理性及已知限制。
- [ ] 对照第五周任务书逐项检查四类交付件，检查图与字典命名一致，业务规则每条可追溯到 FK/约束/代码/人工检查，问题清单能落到第六周。
- [ ] 两名成员分别审阅：一人核对 DDL 与键，另一人核对业务规则与基数；仅记录实际完成的复核，不把 AI 自检冒充组员确认。
- [ ] 更新相关说明入口时保留 v0.1 原貌；检查 `git diff`，确认未更改 `sql/`、`tools/`、`tests/` 及已有结果；**不自动 commit/push**。

## 四、验收标准（逐项可打勾）

- [ ] ER **源文件 + 清晰导出图**齐全，覆盖本组 14 个核心表或合理解释非核心表，命名、PK/候选码/FK 与字典一致，显示所有关系的基数/参与性和图例。
- [ ] `business_rules_mapping.md` 对每条关系有**两端 min/max、适用条件、表/FK、现有实现机制**；数据库约束与期望业务约束分开写。
- [ ] `v01_issues.md` 每项有业务证据、实际约束证据、影响、保留/第六周改进方向；不把未经确认的偏好判定为结构缺陷。
- [ ] `design_validation.md` 可以逐步讲明**多商品订单、会员/散客购买、库存查询**，且能从图跳回数据库表或只读查询与真实结果。
- [ ] v0.1 的 SQL、数据、历史日志和截图未被覆盖或重写；第五周无迁移、无数据库结构修改、无未经授权的推送。

## 五、建议现场讲解顺序（约 8 分钟的内容纲要）

1. 用一句话讲 Token 中转业务以及“产品套餐不等于上游账号库存”。
2. 展示 14 表字典：实体、单行粒度、主码与复合候选码，重点举 `OrderDetails`、`TokenBalances`。
3. 在 ER 总图上沿 **下单—购买明细—会员余额—消耗—上游库存** 走一次，解释 1:N、0..1、必须/可选参与以及中间实体。
4. 展示三种业务场景的表/只读 SQL 对应，说明散客边界。
5. 展示 v0.1 保留项、设计问题和第六周迁移候选；强调当前规则不全是 FK 自动强制的。

## 六、开始执行前的确认点

需要小组确认的**业务判断**，不妨碍先绘制现状图：
- 散客是否允许完全不注册，还是以临时用户记录落单？
- 一张订单中同一商品能否出现多条明细（还是通过 quantity 合并）？
- 每个上游账号是否要求必须存在库存记录？系统自动补货任务由谁作为 `created_by`？
- 规则清单中哪些将来需要数据库即时约束/事务，哪些接受应用层或周期性对账？

**计划结束条件：** 四类第五周作业通过清单验收且版本可追溯；若提出重构，停留在第六周迁移建议，不在第五周实施。


## 七、2026-10-10 实施结果（取代上方初始待办状态）

**执行状态：文档、ER 图、只读验证及自检已完成；人工业务决策与独立同伴复核待办。** 上方清单是制定计划时的原始安排；下面为实际执行记录。

- [x] **P0 基线**：核对 v0.1 DDL、追加 CHECK、原始 ER 草图、Git 状态；现存 `TokenHubDB_v01_A` 只读确认 14 表、17 个启用 FK、3 个追加 CHECK。
- [x] **P1 数据字典**：完成 `week5/data_dictionary.md`，14 张表的实体含义、行粒度、全部字段名/可空性、PK、UNIQUE 候选标识和 FK。
- [x] **P2 关系映射**：完成 `business_rules_mapping.md`；17 条 FK 的两端 min/max、NULL 约束、真实外码和逻辑联系分别列示。
- [x] **P3 图**：完成 `er_diagram.mmd`、`er_diagram.svg`、`er_diagram.png`、本地渲染工具 `render_er.py`；覆盖 14 实体 17 外码。之后按反馈改为不规则避障布局、明确 `0..*` 等文字基数，移除原副标题与图例，重新导出并视觉核对。
- [x] **P4 问题与保留**：完成 `v01_issues.md`，10 项问题/待确认项、7 项保留说明与第六周候选处理，未修改结构。
- [x] **P5 业务场景**：`result/week5/readonly_validation.sql` 实际在 `TokenHubDB_v01_A` 只读运行成功，结果存档为同名 `.log`。100 订单、184 明细、68 多明细订单；订单和库存两类校验异常均为 0；库存阈值下 Gemini 账号为 2。
- [x] **P6 资料归档与入口**：第五周目录 README、数据字典、规则、问题、设计说明、结果证据与根文档入口同步；只添加本周文件及索引。
- [ ] **待小组业务确认**：散客方案、同商品能否同单重复、每上游账号是否必有库存、自动补货创建人。
- [ ] **待同伴独立复核**：由实际第二名组员核对图与 DDL 以及基数，不将 AI 自检冒称人审。
- [ ] **Commit/Push**：未执行；须用户另外明确批准。

**边界**：没有重建、删除或 ALTER 任何数据库；未修改 `sql/`、`tools/`、`tests/` 及旧 `result/` 证据。除本周只读 SQL、日志和报告外未写入数据库。


**最后自检**：`qa_week5.py` 对 14 个实体、17 个 Mermaid 关系与 SQL Server 已有 17 个 FK 逐对校验均通过；SVG/PNG 可解析，当前文档相对链接通过，`git diff --check` 通过。真实记录见 `result/week5/qa.log`。未运行历史 v0.1 全量建库流水线；本周只做增量分析和只读检查。

## 八、特殊 ER 要素复核补充

- [x] 核对严格弱实体、存在依赖实体、多值/复合属性、计算存储字段、关联实体、三方调用事实、同一实体间双角色联系、可选参与性及非标识性外码。
- [x] 17 条真实 FK 在当前物理 PK 下均为非标识性联系，编辑 Mermaid 源关系符为 `..` 并以虚线导出；各关系两端保持 `1..1` / `0..1` / `0..*` / `1..*` 文本，不混同可空性。
- [x] 图中对 `OrderDetails` 标明关联实体，对具体列标明计算存储/汇总存储/快照，并对 `TokenUsageLogs` 标明三方调用事实；**没有依据的弱实体、多值属性及新实体不凭空绘制**。
- [x] [完整审查解释](../week5/special_er_features.md)；本轮仍无 DDL/数据库数据修改，人工小组业务判定仍待完成。
