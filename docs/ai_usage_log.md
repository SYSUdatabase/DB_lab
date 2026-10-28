# 第 5—9 周 AI 使用记录（第二阶段）

本文件仅保留第二阶段第5—9周的原始过程记录。第1—4周与整理前完整版本在 [archive](../archive/coursework/week4/ai_usage_log_full_history.md) 保留，未将历史失败记录伪装为成功。

## 2026-10-10：第五周 ER 可编辑图制作与用户逐轮纠偏

> **记录类型**：当前对话中 AI 实际操作的增量记录。这里写“用户决定”，不将其未经确认地归于某位组员。此节是对第五周作图的详细补充；第四周技术案例仍保留在前文。

### 第 1 轮：建立可编辑的物理 ER 图

- **用户任务**：按第五周计划执行，并在项目 `D:\Desktop\DB\DB_lab` 中完成图、规则映射与验证。
- **AI 操作**：从现有 DDL、约束文件建立 `report/week5/er_diagram.mmd`，使其覆盖 14 表、17 FK；使用 `render_er.py` 生成 SVG 与 PNG；同时保存 `business_rules_mapping.md`、`data_dictionary.md` 和只读验证证据。
- **初版问题**：使用固定方阵式布局、较多线交叉、符号化的 `|| / o| / o{ / |{` 端点标记，以及额外的周次/外码数量副标题；文件可生成不等于适合阅读。
- **实际证据**：`result/week5/readonly_validation.log` 的 14 表/17 FK 只读结构输出。此证据用于对照关系，不涉及密钥字段取值。

### 第 2 轮：布局、基数文字和删减图面信息

- **用户原话要点**：“最终形状不用太规整，首先保证线尽量不要交叉”；“1..N这些不要用奇怪的符号代替”；“用1..*而不是1..N”；删除截图中的无用副标题和符号图例。
- **偏离与纠正**：AI 一度直接生成过 ER 图片，但用户明确指出“不要直接生成，而是用那个可编辑er图生成”，要求在 sh 电脑内直接操作项目。直接生成的图片**没有被采用为正式作业文件**。
- **实际改动**：重写 `render_er.py`，通过不规则手动布局、端口分配、基于障碍/折线代价的 A* 路径搜索避开实体框；输出 `1..1` / `0..1` / `0..*` / `1..*` 文本基数，删除副标题和图例，重新导出 `er_diagram.svg/png`。`er_diagram.mmd` 仍是实体/联系的唯一可编辑来源。
- **两条线的答疑**：用户质疑 `Employees`—`RestockTask` 的双连线，AI 从 DDL 识别 `created_by NOT NULL` 与 `assigned_to NULL` 两个独立 FK，决定保留两条线并分别标注角色，而不是合并为一条线。
- **审查边界**：A* 避障是改善可读性的实现手段，不等于从数学上证明所有连线 0 交叉；重新生成的图经视觉查看，但未有独立组员签字。

### 第 3 轮：弱实体、多值属性和特殊 ER 语义

- **用户原话**：“注意有没有弱实体，多指等特殊需要表示的”。
- **AI 重新核对**：比较 PK、UNIQUE、FK 的实际列：`OrderDetails.detail_id`、`Inventory.inventory_id`、`TokenBalances.balance_id` 是各自独立 PK；17 条 FK 均不属于子表 PK。
- **技术修正**：把可编辑 Mermaid 中这 17 条联系统一标为非标识性 `..`，Python 导出对应虚线，显式强调**虚线与可空不是同一件事**；图中提示 `OrderDetails` 为关联实体，`TokenUsageLogs` 为三方调用事实，并将 `subtotal` 和明细 Token 的公式列标为“计算存储”，订单汇总/周期汇总/余额与库存快照分别标注。
- **拒绝凭空新增的元素**：严格弱实体的双矩形、多值属性双椭圆、复合属性层次、ISA 继承、真实 DDL 不存在的物理联系，因缺乏结构与业务证据而**未画**。
- **详细结论**：`report/week5/special_er_features.md`；`data_dictionary.md`、`business_rules_mapping.md` 和 `design_validation.md` 已同步说明实际物理模型与业务期待的区别。

### 第 4 轮：文档追溯与验收

- **用户本轮要求**：把前述作图修改写进 AI 使用文档，并把“边修改边记录”的纪律写入 `AGENT.md`。
- **实际操作**：保留 `docs/ai使用文档.md` 中第四周原始正文，新增独立的第五周作图补充；在 `AGENT.md` 增加“AI 使用文档：边修改边记录（必须遵守）”，要求每次有效修改或失败纠偏后及时更新记录，写明原始要求、AI 方案、人工取舍、文件、真实验证和遗留事项，而非事后笼统补写。详细时间线补充至当前文件。
- **之前已运行的检查**：`python report/week5/render_er.py` 导出；`python report/week5/qa_week5.py` 将 14 表、17 联系与既有 SQL Server 外码证据对照，解析 SVG/PNG、检查页面文字及相对链接；`git diff --check` 在 ER 修改后通过。最新特殊图检查记录为 `result/week5/qa_special_er.log`。本轮 AI 文档增补后的检查结果应另见本节后续增量记录，不可把先前 QA 当成已经验证本次新文档。
- **未完成**：独立组员对 ER 图和业务定义的复核；匿名散客、单订单同商品重复明细等仍需小组确认。本次仅文档/图示范围的修改，不运行建库或迁移；**未就本轮变更执行 commit 或 push**。

**后续执行规范**：对 AI 辅助变更要遵循 `../AGENT.md` 的“边修改边记录”约定，每完成一轮就追加可追溯记录；如下一轮纠正本节结论，应增加新条目而非无痕改写历史。


### 本次 AI 文档与 AGENT 约定的实际校验（2026-10-10）

在增补 `docs/ai使用文档.md`、本日志和 `AGENT.md` 的同步记录规则后，实际执行：针对新增第五周 AI 文档段落检查相对链接（提交正文 **4** 条，详细日志新章节 **0** 条，全部通过）；`python report/week5/qa_week5.py` 仍返回 **14 实体/17 FK、SVG/PNG 可解析及 11 份文档链接通过**；`git diff --check` 返回 0。输出含 Windows CRLF/LF 行尾提示，但不是检测失败。本轮不把自动 QA 记为独立组员复核，也没有执行新的数据库查询或修改。作图更改及本次文档更改依然保持 Git 未提交状态。


---

## 2026-10-10 第五周 ER 图双外键说明与实线修订

### 1. 用户提出的问题

> “还有C:\\Users\\ruanyicheng\\Desktop\\数据库\\DB_lab\\week5\\er_diagram.png里面现在连接实体的线怎么是虚线，要改成实线。另外Empolyees实体和RestockTask实体之间连了2条线，说是有2个外键，这个肯定也是要进行说明的。”

用户随后明确指出脚本位置并要求将对话留档：

> “C:\\Users\\ruanyicheng\\Desktop\\数据库\\DB_lab\\week5\\render_er.py 就在这里，另外把我发现的`Employees -> RestockTask` 两条线 并让你说明的对话放到C:\\Users\\ruanyicheng\\Desktop\\数据库\\DB_lab\\docs\\ai_usage_log.md里面”

### 2. 外码说明与处理决定

- **针对两条线**：这并不是同一联系重复绘制，而是 `RestockTask` 引用 `Employees.employee_id` 的**两条独立外码**，表示创建人和被指派人这两个不同业务角色。必须在图上同时保留、分别命名、分别标参与约束。
- **创建人外码**：`RestockTask.created_by INT NOT NULL`，约束名 `FK_RestockTask_CreatedBy`。每个任务必须对应恰好一个创建员工（任务→员工 `1..1`），员工可创建零到多个任务（员工→任务 `0..*`）。
- **指派人外码**：`RestockTask.assigned_to INT NULL`，约束名 `FK_RestockTask_AssignedTo`。任务可以尚未分配员工（任务→员工 `0..1`），员工可被指派零到多个任务（员工→任务 `0..*`）；创建者和被指派者可以相同，也可以不同。
- **针对虚线**：用户希望提交的 PNG 用实线表示实体间真实联系。AI 原先采用 Mermaid 的 `..` 非标识性关系，并用 Python 渲染成虚线；本轮决定**正式 SVG/PNG 全部改为实线**，不把线型用作“FK 是否参与子表 PK”的依据。为了不错误地把关系改成标识性，`er_diagram.mmd` 仍保留规范的 `..`；直接交给 Mermaid 渲染可能显示虚线，课程交付应使用同目录 `render_er.py` 输出的 PNG/SVG。
- **针对 v0.1 是否“全改好”**：AI 澄清答案为“没有”。第五周是发现、人工技术复核、解释和形成问题/改进清单；订单非空明细、真正匿名散客等原始物理结构缺口仍如实登记，不应宣称 v0.1 全部解决，也不在本周迁移真实库。

### 3. 修改文件

- `week5/render_er.py`：所有 FK 的 SVG/PNG 线型统一为**实线**；`Employees→RestockTask` 的两个角色外码使用紫色连线、保留 `created_by` / `assigned_to` 独立标记；图例增加“created_by=创建人（必填）/assigned_to=被指派人（可空）”。
- `week5/er_diagram.mmd`：补充说明“源 Mermaid 的 `..` 是非标识性语义；正式导出图可用实线”，没有把真实非标识性外码误改为主码的一部分。
- `week5/README.md`、`business_rules_mapping.md`、`design_validation.md`、`special_er_features.md`、`data_dictionary.md`：同步纠正此前“导出图为虚线”的描述，单列解释这两条 FK 的业务含义、必需/可选参与。
- `week5/qa_week5.py`：增加“SVG 不得含虚线样式”以及“实线、双角色外码、两个 FK 名称必须出现”的回归断言。

### 4. 验证结果

在 Windows 项目根目录执行 `python week5/render_er.py` 成功重新生成 `er_diagram.svg`、`er_diagram.png`。实测 SVG 的 `stroke-dasharray` 出现次数为 **0**，`created_by`、`assigned_to`、`实线` 均存在；PNG 为 **3250 × 2041**。运行 `python week5/qa_week5.py`：**14 实体、17 条关系匹配、SVG/PNG 可解析、12 份相关文档链接有效**。新增断言检查通过。

本轮只修改图形、第五周文档及 AI 日志，未改动数据库，未执行 Git 提交。

---

## 2026-10-14 第六周规范化与迁移计划

1. **输入与审查**：用户上传《第六周任务讲解.docx》及 AGENT 协作约定；AI 只读检查 sh 电脑 `D:\Desktop\DB\DB_lab` 下 `AGENT.md`、`week5/`、`sql/v01/01_create_tables.sql`、`sql/v01/README.md`、`tools/run_v01.ps1`、`README.md`、第五周复核记录。
2. **识别的技术约束**：14 张表、17 条外码；`OrderDetails` 有 `detail_id` 与 `(order_id,product_id)` 两种标识，`Products.price` 不能替代成交快照，`Inventory` 和 `TokenBalances` 存在状态快照，`UsageSummary` 是周期汇总。范式分析必须覆盖全部候选码；是否调整须业务依据而非样例重复。
3. **AI 形成方案**：写入 `plan/week6-normalization-migration-plan.md`，将工作分为 P0 基线副本与三类对账、P1 函数依赖与三种异常、P2 目标结构/无损与依赖保持、P3 副本迁移、P4 数据/完整性/权限回归、P5 第二阶段文档与证据。包含保留路径和实迁移路径两种可能，待 P1/P2 决策后确定。
4. **执行边界**：目前仅形成计划，没有执行 SQL、备份、还原、迁移、数据修改或 commit/push；不存在迁移结果和新库回归结论，不能登记为已完成。用户未批准实际迁移之前保持 v0.1 不变。

## 2026-10-14：第六周 P0 / P1 启动
- 用户授权按第六周计划实施。检查 sh 电脑当前只有 `TokenHubDB_v01_A`，工作区已有第六周计划与上次 AI 日志的未提交更改；本轮不会擅自提交。
- 只读检查：源表 `OrderDetails` 的 `subtotal`、`total_tokens` 目前是实际存储列，另有两个同表公式 CHECK；`v_OrderDetail`、`v_ProductSales` 依赖该表，但不是 schema-bound；数据库内含四个 hub 数据库角色。
- **优先方案**：不调整四项尚未确认的业务规则，不改变订单价格快照；若基线数据和公式检查符合条件，在隔离副本上将两个可由同一行字段计算的明细小计改为 SQL Server 持久化计算列，从数据库端消除手工维护的同表冗余。完整 FD/范式分析另行论证，不把计算列调整称为所有表已达 3NF。
- 首次只读元数据查询误用了 `sys.database_principals.state_desc`（不存在），SQL 返回 207；纠正查询后成功，未产生库级修改。

## 2026-10-14：P0 数据隔离完成
- 源库只有 `TokenHubDB_v01_A`。在 SQL Server 默认备份目录新增 `TokenHubDB_v01_A_W6_20261014.bak`（不放入 Git），执行 `BACKUP ... COPY_ONLY, CHECKSUM`、`RESTORE VERIFYONLY` 与 `RESTORE DATABASE ... WITH MOVE` 成功。目标库为 `TokenHubDB_v10_W6_20261014`，MDF/LDF 使用独立目标路径，未覆盖原库文件。
- 命令及输出位置：`week6/prepare_copy.sql`、`result/week6/baseline/prepare_copy.log`；备份校验与还原返回码 0。此前先检查备份路径、目标数据文件和目标库均不存在。未查看任何密钥/凭据字段取值。

## 第六周 P0 修复基准与对账（2026-10-14）
- 第一次执行 `week6/baseline.sql` 在读取数据库角色权限元数据时返回 SQL 451：系统目录与用户库字符串拼接时 collation 冲突。错误输出保留于 `result/week6/baseline/source_semantics.txt`，不覆盖失败证据。
- 对该 SELECT 的系统目录字符列显式指定 `COLLATE DATABASE_DEFAULT` 后，以新文件名 `source_semantics_v2.txt`、`copy_before_v2.txt` 分别核对源库及还原副本。两份文件各 3837 行，SHA-256 **A73CB20D7DAA334328AABC25EB06CDD4FE6977F20C2EF86302406176AACB8EEC** 完全一致；订单、明细、销售、库存、余额、汇总和角色权限基线一致。
- 尚未执行第六周结构迁移；严格保护源库与最初副本基准。

## 第六周 P1/P2：范式判断和候选迁移方案
- 新增 `week6/fd_checks.sql` 与 `result/week6/baseline/fd_checks.log`，只读确认明细 subtotal/Token 公式无异常、库存和订单汇总一致、相同 `(period_type,period_start)` 未出现不同 `period_end`（样例不能证明业务 FD）。daily/weekly/monthly 日差分别 0/6/29～30。
- 在 `week6/dependency_normalization.md` 逐表列出 14 表的所有 DDL 候选码、主要业务 FD、1NF/2NF/3NF、插入/修改/删除异常；将 `OrderDetails` 公式存储列归为受约束的理论非 3NF，并标出 `UsageSummary` 按统一周期规则才会成立的部分依赖。
- 在 `week6/redesign_decisions.md` 提出有条件把 `period_end` 拆到 `UsagePeriod(period_type,period_start,period_end)`，说明交集决定新周期表、无损连接、依赖保持、应用写入兼容和权限影响。用户尚未确认全局周期业务规则和实际迁移范围，未执行 P3 业务表 DDL；原库和副本迁移前基准保持不变。

### P2 代码级交叉核对

只读查看 `tools/datagen.py` 的汇总周期生成逻辑及 `sql/v01/verify.sql` VFY10：前者按周一到周日、自然月首末生成，后者按同一算法验收，因而固定周期 FD 有项目规则支持。对隔离副本只读查询：3394 行 UsageSummary、99 种 `(period_type,period_start)`（daily 83 / weekly 13 / monthly 3），同键不同 period_end 计数为 0。更新第六周依赖与设计说明，但仍不修改原库或副本结构；正式目标迁移范围尚待用户批准。

### P2 文档自检与命令修正

- 首次用 PowerShell here-string 通过管道传 Python 标准输入检查链接，输入首字节携带 UTF-8 BOM，Python 返回 `SyntaxError: invalid non-printable character U+FEFF`；该调用未修改项目文件或数据库。随后改用 PowerShell 自身的只读 Markdown 相对链接检查。
- 重新检查 `README.md`、`week6/`、`result/week6/README.md` 和计划共 42 条相对链接，**0 条失效**；`git diff --check` 通过。 `week5/qa_week5.py` 重新核验 14 张表、17 条 FK、图像与 12 份文档引用通过。
- 源库和隔离副本的基准均有成功文件；第一次 collation 451 错误见 `result/week6/baseline/source_semantics.failed_collation.txt`，`source_semantics.txt` 和后缀 v2 的对账文件均为有效版本。无 P3/P4 结果，等待用户批准具体目标模式。

## 2026-10-14：P3 获批准并设计迁移脚本
- 用户要求“commit后批准执行”。已先提交 P0–P2 基线与设计：`43b5112 docs(week6): establish normalization analysis and copy baseline`；未 push。随后才开始迁移准备。
- 为避免原有查询接口失效，最终实施路径选择将原 `dbo.UsageSummary` 改名为 `dbo.UsageSummaryCore`，把 `period_end` 提取至新表 `dbo.UsagePeriod`（周期复合主码），再以同名 `dbo.UsageSummary` 只读兼容视图还原旧 10 列读路径；原 CRUD 许可随实体表迁移，新增周期表由 manager 持有 CRUD，原同名视图授予 manager SELECT。旧 INSERT（含 IDENTITY_INSERT）不再通过视图写入，后续须使用 v1.0 写入路径，v0.1 生成器不改动。
- 迁移脚本 `sql/v10/migration.sql` 强制检查数据库名 `TokenHubDB_v10_W6_20261014`、原表/行数/17 FK、周期定义和权限状态；用单事务与 TRY/CATCH，失败回滚。脚本仅对隔离副本有效，绝不执行在 `TokenHubDB_v01_A`。

### P3 第一次执行失败及根因
- 第一次在隔离副本运行 `sql/v10/migration.sql` 报 51610（迁移后表/FK/视图数量检查不满足），`result/week6/migration/run.log` 保留失败输出。
- 失败后只读核对发现副本回到旧 `UsageSummary` 表（14 表、17 FK、无 UsagePeriod/UsageSummaryCore），说明事务回滚生效。基线源库和副本都只有 **9 个视图**，而仓库 `sql/v01/view.sql` 定义 **10 个**，缺失 `dbo.v_CustomerService`；因此迁移中新增兼容视图后只有 10 个而非预计 11 个。该源库比 README 描述的当前 v0.1 不完整。
- 处理计划：**不修改源库**；将官方 `sql/v01/view.sql` 已声明的 `v_CustomerService` 定义和原来角色应有的 manager/staff 只读权限作为隔离副本的显式修复步骤纳入迁移，并重新进行安全校验与回归。不会把 9 视图的源库冒充为 10 视图。

### P3/P4 完成与 v0.1 基线缺陷
- `sql/v10/migration.sql` 修订版第二次执行成功（`result/week6/migration/run_v2.log`）；得到 15 张表、18 个启用且可信外码、11 个视图、99 条周期定义、3394 条不丢失的 UsageSummary 明细。旧逻辑读接口以兼容视图还原，原写入接口调整为 `dbo.UsageSummaryCore` 与 `dbo.UsagePeriod`。
- `sql/v10/regression.sql` R01—R12 全部通过，包含与源库双向 EXCEPT、合法写入后回滚、候选码/检查约束/FK 反例、角色权限及原库未变。迁移前后 3763 条业务基准记录（排除有意新增的权限对象）差异为 0。
- 从正式 `sql/v01/verify.sql` 派生 `week6/verify_v10.sql`，仅适配目标库名、15 表/11 视图预期。第一次检查发现源库旧 `v_InventoryStatus` 缺少 `quota_headroom`；在副本执行 `week6/align_legacy_views.sql` 使用正式 `sql/v01/view.sql` 的视图定义补齐，原 v0.1 不改。
- 完整校验随后通过 VFY01—VFY11，但在 VFY12 报 51360。源/目标各自查询现存问题数完全一致：订单早于注册 20、调用早于注册 402、调用与上游有效期/provider 不符 225、逐事件历史负余额 1（`result/week6/regression/legacy_anomalies_{source,target}.log`）。属于复制的旧数据缺陷；未为掩盖错误而改写交易历史。VFY12/13 **不能记录为通过**，原库全量验收口径需另行纠正。

### 第六周 P5 最终交付与 QA

- 生成 `week6/er_diagram_v10.mmd` 与 `render_er_v10.py`，初次程序替换把 PowerShell 的转义序列误写入 Python 源文件，触发 SyntaxError；纠正两处布局/路由字典项后，成功从可编辑 Mermaid 源导出 SVG/PNG。图包含 15 张物理表、18 条实际 FK，基数为 `0..1/1..1/0..*/1..*`，保留 Employees→RestockTask 两种独立角色联系。完成 `data_dictionary_v10.md`。
- 使用 `sys.foreign_keys` 生成 `result/week6/regression/actual_fks.txt`，由 `week6/qa_week6.py` 对照每条 FK 的父/子表及复合外码列，15 实体/18 FK 完全匹配，SVG/PNG 解析通过。
- 运行 `week6/verify_v10_roles.sql` 独立 VFY14，全部通过；R01–R12 修复库存视图后再次通过，旧源库后置基准哈希仍为 `A73CB20D7DAA334328AABC25EB06CDD4FE6977F20C2EF86302406176AACB8EEC`。
- 单元测试第一次 PowerShell 设置 ErrorActionPreference Stop 时把 unittest 正常 stderr 进度当成 NativeCommandError；重新通过 cmd 重定向运行，22 项测试中 12 PASS、10 因未配置隔离集成测试库而 skipped，不计为集成验证成功；其余 SQL 回归证据来自独立脚本。ER QA 及文档链接检查通过。
- 更新第六周数据字典、设计方案、报告、根 README、ROADMAP、要求索引和 AI 使用文档。旧 VFY12/13 缺陷四项原库与新副本均一致，继续保留为 FAIL，等待独立的数据质量修复决策。没有新的第二次 Git commit/push。

### 交付前质量检查收尾

- 第六周 `week6/qa_week6.py` 对 15 物理表/18 真实 FK 的所有列组合与 Mermaid 实体/关系逐条匹配，通过 SVG/PNG 和 56 条相对链接检查；第五周 QA 重跑亦通过。
- 第六周两个 Python 文件 AST 检查通过。旧项目单元测试共 22 项，12 PASS、10 skipped（明确禁止把 skipped 算通过）；原电脑未发现仓库 `.venv` 或 `ruff`，本轮未执行 Ruff check/format。SQL 回归 R01—R12 和 VFY14 的 PASS 来自独立执行日志，不使用单元测试 skipped 充当证据。
- `git diff --check` 已通过（有 Windows 行尾格式提示但非错误），目录仍有本次新增/修改文件**未提交**，没有第二次 commit/push。目标数据库已迁移，原 `TokenHubDB_v01_A` 的业务基准哈希未变。

## 2026-10-14：第五周问题修复启动（v1.1 隔离试验）
- 用户指示“那就现在解决”，授权在 sh 项目内推进，但没有给出 I02/I03/I04/I07 等业务歧义的具体选择。先落实不改变现有业务含义的保护措施；涉及匿名散客、同单商品重复等不擅自定案。
- 已只读核对 v1.0 库及正式 DDL/role 定义，确认 I01、I05、I08、I09 相关字段。现有 InventoryLog 有 restock_task 4 行、manual 3000 行且后者均带编号；ExceptionLog 当前使用 Orders、Inventory、TokenUsageLogs 三种对象引用，各 4 行。历史引用关联目标当前均存在，但 SQL 未以真实 FK 强制。
- 从 v1.0 隔离数据库 COPY_ONLY/CHECKSUM 备份、VERIFYONLY，独立还原为 TokenHubDB_v11_Issues_20261014。保留 v0.1、v1.0 原库，备份不放在 Git。预备实施新写入约束和原子化消费流程，测试只在 v1.1 副本进行，历史异常不无依据地改写.

### v1.1 第一批约束与原子化调用测试（2026-10-14）
- 新建 `week6/v11/enforce_known_rules.sql`，仅部署在 `TokenHubDB_v11_Issues_20261014`。新增五类 AFTER 触发器：已支付/退款订单至少一条明细并核对汇总；已完成订单禁止直接改明细；新增使用记录检查注册时间/provider/上游使用区间；新库存流水的 order/restock_task 引用验证；新 ExceptionLog 的 Orders/Inventory/TokenUsageLogs 引用验证。`manual` 类型参考号没有已确认目标，不伪造 FK。
- 第一次 `test_guards.sql` 在最后一项因测试样例 `ExceptionLog.exception_type='test'` 触发既有 CHECK，而不是新引用约束。失败日志 `result/week6/issue_fixes/test_guards_01.log` 保留。改为既有合法 `system_error` 后重跑，六项正反例全部通过，见 `test_guards_02.log`。未覆盖失败证据。
- 新建 `week6/v11/record_usage.sql`：`usp_W5_RecordUsage` 在事务内对有效用户/套餐/账号、余额和库存加锁，检查 provider、时间范围及余额/配额；同事务更新 TokenBalances、UpstreamAccount、Inventory、TokenUsageLogs、InventoryLog、UsagePeriod、UsageSummaryCore。只授予 `hub_manager` EXECUTE。新写入正例和余额不足反例见 `test_managed_usage_01.log`；正例在外层事务回滚，余额/库存/上游配额及日志记录恢复，错误 51956 拒绝超额消费。
- 边界：历史数据没有重写；当前管理员仍有旧版直接 DML 授权，因此不把该过程宣称为所有写入路径的强制单一入口。I02/I03/I04/I07 仍涉及未确认的业务选择，后续需明确口径。

### v1.1 审计引用保护、回归及数据对照

- 第二批 `protect_parent_deletes.sql` 新增普通管理员不能直接插入/更新/删除 TokenUsageLogs 的触发器，以及对已知多态审计引用目标的删除保护。 `test_parent_and_role_01.log` 验证管理员直写事件被 51982 拒绝，Orders 和 RestockTask 被引用时删除分别被 51983/51985 拒绝。
- 第一批原子化存储过程在第二批触发器部署后重新执行 `test_managed_usage.sql`：正例事务回滚、余额不足错误 51956，均通过，见 `test_managed_usage_02.log`。
- `regression_v11.sql` 从正式 `sql/v10/regression.sql` 仅更改 v1.1 目标库白名单，R01–R12 再次全部通过。用 `week6/baseline.sql` 提取副本业务数据，与原 v1.0 `copy_after.txt` 对照，排除有意新增的对象权限行后，两侧各 3763 行、差异 0。
- 以上成功不等于旧历史业务违规已清零：第五周 I02/I03/I04/I07 未确定业务选择，I05/I06/I08/I09 仍有直接父表/余额维护及不明 manual 参考编号等待闭环。

### 2026-10-14 I02/I03/I04/I07 用户明确决策
- 用户批准：I02 同订单同商品通过 quantity 合并、保留 UNIQUE；I03 散客必须先有 Users 记录、Orders.user_id 继续 NOT NULL/FK；I04 每个上游账号必须存在且仅有一个 Inventory；I07 创建补货任务区分 manual/system，manual 必填员工，system 不需要员工。
- 读库核验：v1.1 库仍为 15 表、18 FK、已有 10 个触发器及原子化调用过程；RestockTask.created_by 当前仍 NOT NULL、created_source 不存在；现有上游账号缺少库存的计数为 0。
- 待实施 SQL 将仅运行在 TokenHubDB_v11_Issues_20261014，原 v0.1/v1.0 继续不修改；保留首次运行和反例证据，不创建任何账户密钥或用户真实密码数据。

### 2026-10-14 I02/I03/I04/I07 已授权决策实施与失败修复
- 在隔离 v1.1 副本部署 `week6/v11/approved_rules.sql`：保留同单商品联合唯一，RestockTask.created_by 改为可空并增加 created_source、默认 manual 及可信 CHECK；新增上游账号自动建立库存、阻止库存删除/改绑造成缺口、订单插入前必须已有 active Users 记录的三个触发器。
- 初次安装因 SQL Server 在同一批次内编译对刚创建的 created_source 列的引用报 207，事务回滚；第二次取消最终验证直接列访问后依旧在 ADD CHECK 同批次编译时报 207，检查确认安装未部分生效；第三次将 ADD COLUMN 与 ADD CHECK 分成两个 GO 批次，成功。失败日志 approved_rules_install_01.log / _02.log 完整保留，成功日志 approved_rules_install_03.log。
- 新增 `usp_W5_CreateRegisteredOrder`（existing active Users 方可创建）和 `usp_W5_AddMergedOrderItem`（仅待支付单，商品按 quantity 合并、旧成交价格快照保留，同事务更新 Orders 金额/Token）。安装成功：registered_order_workflow_install_01.log。
- `test_approved_rules_01.log` 六组情形全部通过：同商品数量 2+3 合并到 5、无账户直接/过程下单被拒、创建账号立即有唯一正确额度快照、库存删除拒绝、系统补货 created_by=NULL 和人工补货 created_by 必填的正反例均通过，所有业务写入事务回滚。
- 老四组测试 `test_guards.sql`、`test_managed_usage.sql`、`test_parent_and_role.sql`、`regression_v11.sql` 重新执行全部通过，分别保留后缀 postapproval.log。
- 使用可编辑 ER 源生成独立 `er_diagram_v11.mmd` 与 SVG/PNG，保留 v1.0 原图不覆盖，库存参与基数改为 1..1，RestockTask 创建人基数改为 0..1，补充 created_source 字段。没有变动源 v0.1/v1.0 数据库。

### 2026-10-14 I02/I03/I04/I07 验收补充

- `approved_rules.sql` 首次两次失败，均为 SQL Server 207（同一批次引用刚添加列）；分别保存 `approved_rules_install_01.log` 和 `approved_rules_install_02.log`，读取元数据确认恢复到 10 个旧触发器/18 FK、无 created_source；加入 GO 后在 `approved_rules_install_03.log` 成功。
- `registered_order_workflow.sql` 成功创建 `usp_W5_CreateRegisteredOrder` 和 `usp_W5_AddMergedOrderItem`（保留首次成交单价快照、更新订单汇总）。`test_approved_rules_01.log` 六类结果 PASS；又补充同单同商品直接重复 INSERT 的 UNIQUE 负例，`test_approved_rules_02.log` PASS。
- `verify_approved_rules.log`：8 个上游账号对应 8 条库存，8 个存量补货任务转为 manual；可信 FK/CHECK 与 13 个启用触发器 PASS。四个旧 v1.1 测试及 R01–R12 再次通过（见 postapproval 后缀日志）。
- v1.1 独立可编辑 `er_diagram_v11.mmd` 与渲染器/导出 SVG/PNG 已创建：库存父→子改为 1..1，RestockTask.created_by 变为可选、加入 created_source。与 v1.0 的非权限业务基准两侧各 3763 行，差异 0。

## 2026-10-14：按业务板块新增项目总览图（进行中）

- 用户要求换一种图理解整个数据库项目，分板块而非继续阅读 15 表 18 外码的密集 ER 图。已只读核对当前 v1.0 迁移说明、目标数据字典、根 README 与业务流程。工作区存在此前未提交的第六周迁移/修补文件，均须原样保留；不执行数据库修改。
- 采用六板块：身份与权限、套餐与订单、余额与调用、上游与库存、用量统计、异常与经营处理；每个物理表只归到一个主板块，总计 15 张。特别注明 UsageSummary 是只读兼容视图，不是第 16 张物理表；v1.1 独立修补不混入 v1.0 结构图。
- 新增可编辑 Mermaid 源 `report/overview_modules.mmd`，与第五/六周 ER 图并存，不覆盖原图。下一步从该源文件生成 SVG/PNG 并核对图面与物理表数。

### 用户批准规则实施后的最后核验

- v1.1 SQL 元数据只读检查：15 表、18 可信 FK、13 个启用 W5 触发器，8 个上游账号/8 条库存、8 个现存补货任务且均为 manual，created_by 可空但 manual/source CHECK 可信。见 `result/week6/issue_fixes/verify_approved_rules.log`。
- 测试新批准规则 `test_approved_rules_02.log` 全部 PASS；原 `test_guards_postapproval.log`、`test_managed_usage_postapproval.log`、`test_parent_and_role_postapproval.log` 以及 `regression_v11_postapproval.log` 全部 PASS。最新业务基准非权限记录两侧各 3763 行，差异为 0，模拟业务写入均回滚。
- v1.1 可编辑图的 15 实体/18 FK、库存 1..1 与 RestockTask.created_by 0..1 基数、SVG/PNG 解析 QA 通过；旧第五周/第六周 QA 通过；检查 133 条文档相对链接均存在，`git diff --check` 成功。
- Git 中仍保留了先前未提交的第六周迁移与本轮 v1.1 文件；没有执行 commit/push。仓库出现一个未跟踪的 `report/overview_modules.mmd`，本轮没有创建或修改该文件，保留原状。

### 第六周项目总览 HTML：用户改选后的实际修改与测试（2026-10-14）

- **反馈与取舍**：用户先请求替换复杂 ER 关系图、分板块理解项目，AI 曾新增可编辑 report/overview_modules.mmd、渲染器及 SVG/PNG；随后用户明确改选 HTML，故新增 HTML 作为主要展示方式，保留之前可编辑/静态资料而不覆盖 ER 源。
- **本次新增文件**：report/overview_modules.html，无外部 CDN、无网络请求和数据库连接。六块合计 15 张物理表，支持点击业务步骤、选择板块、选择具体表、筛选表名或业务概念，并展示 PK、候选码、FK、特殊关系与 v1.0 的周期拆分。
- **内容依据**：week6/data_dictionary_v10.md、week6/README.md、sql/01_create_tables.sql 与根 README 的业务流程。强调 UsageSummary 是只读兼容视图，不能当第十六张表，历史价格快照不能改为现价；操作界面只负责说明业务，不假设支付/扣费完整事务已自动实现。
- **检查证据**：在 sh 电脑上通过 Node --check 检查嵌入脚本；Chrome headless 输出首屏截图至系统临时文件并人工目视检查；Puppeteer 无头交互返回 HTML_UI_PASS：六卡渲染、用量统计板块选中、UsageSummaryCore 复合外码详情、UsagePeriod 搜索、业务流程导航及无页面 JS 错误。测试仅验证 HTML 交互，不意味着整个数据库回归再次运行。
- **收尾**：项目 README/ROADMAP 和 AI 文档补充 HTML 入口。没有改动数据库、旧 ER 文件或旧 SQL；未执行 commit/push。

## 2026-10-14：用户要求追加第六周迁移前完整代码备份并验证独立复现
- 先只读检查 Git 历史，确定第六周首个提交是 `43b5112`，其父提交 `c8d4e64`（2026-10-10）为第六周开始前的项目版本，344 个已跟踪文件。仓库现有 5 个未跟踪 `report/overview_modules.*` 不纳入历史快照，也不覆盖。
- 仅按历史 Git 树路径扫描敏感文件名，未发现 .env、密钥、私钥、密码、CDKey、证书或 SQL Server 备份等文件名；未读取凭据值。使用 `git archive --format=zip c8d4e64` 创建 `archive/week6-pre-migration/DB_lab_pre_week6_c8d4e64_full_source.zip`（344 文件，5,237,257 字节；SHA-256 `D2DFA2F23504050ACBA3F4BDE95A7946DCA72D29F6599A6D75A67C16DDE5743C`），另写 344 项原始 Git blob 路径/对象清单 `source_manifest.txt`，不重写压缩包。
- 首次 PowerShell ZIP 检查缺少 `System.IO.Compression.FileSystem` 程序集而失败，压缩包创建成功但后续验证未运行；引入正确程序集后验证 344/344 文件并核对核心 SQL/Python/测试路径均存在。无数据库更改。
- 下一步将从不修改的 ZIP 解压到全新目录，使用其中旧版代码重新建独立测试库，再验证第六周迁移能否实际复现；历史 SQL Server 备份需单独保存，不能用代码快照代替完整数据备份。

### 第六周完整代码复现：已运行的分步和自动测试（2026-10-14）

1. 首次从冻结的 `c8d4e64` ZIP 解压 344 个文件到新的 `D:\Desktop\DB\DB_lab_replay_c8d4e64`；用快照自己的 `tools/run_v01.ps1` 创建新 `TokenHubDB_v01_W6Replay261014`，原建库、建表、数据、CRUD、view、query、constraint、role、verify、signature **全部 PASS**。
2. 原代码构建的数据库为 14 表/17 FK/**10 视图**，UsageSummary 3394 行、99 个周期，与历史本地 v0.1_A 的 9 视图不同。修改现有 `sql/v10/migration.sql` 的前置版本判断为严格允许 9 或 10 视图，只有缺 `v_CustomerService` 的 9 视图分支才补建；10 视图分支避免重复创建。其它未知状态继续 THROW。
3. 用新备份 `BACKUP COPY_ONLY/CHECKSUM` / `RESTORE VERIFYONLY` / `RESTORE ... WITH MOVE` 复制新 v0.1 至 `TokenHubDB_v10_W6Replay261014`；迁移前源/副本基准 SHA-256 同为 `A12B5ED2FFD832C2DC5DDC7988446212E8D18695260A90382B94F060286C5FF5`。用当前迁移模板派生受新目标名限定的 SQL 文件，实际迁移成功，R01–R12 和全套 VFY01–VFY14 **PASS**。记录在 `result/week6/reproduction/`。
4. 编写 `week6/reproduction/run_from_snapshot.ps1`，采用严格后缀验证、ZIP SHA-256、文件/数据库已存在即停止、SQL Server 默认数据/备份路径、仅新命名目标及独立复制出的 SQL 验收脚本。第二次完整调用 `-Suffix W6Auto261014`，19 秒左右实际完成，两套新的数据库及物理文件均独立，R01–R12、VFY01–VFY14 **PASS**，非权限业务记录 3763 条差异 0，日志含回放 manifest。
5. 加入只读 `week6/reproduction/qa_reproduction.py`。首次 QA 尝试把 PowerShell UTF-16 转录作为 UTF-8 解码而失败；增加基于 BOM 的 UTF-16/UTF-8 识别后，又误认为 VFY01 也必须有 `PASS VFY01` 字符串，实际旧校验在 VFY01 输出每表计数和最终汇总 PASS；将 QA 改为检查 VFY01 表头及 VFY02–VFY14 PASS、完整最终 PASS。随后检查 ZIP、清单、R01–R12、VFY01–VFY14、源/副本对账及 3763 行全部通过，未篡改测试日志。
6. 历史本地 `TokenHubDB_v01_A` 仍保留历史时间/provider/余额异常，v1.1 业务修复副本也未被本次复现脚本覆盖。未跟踪 `report/overview_modules.*` 和同期 HTML 文档修改属于另一个任务，本轮不删除或覆盖，也不将它们并入这份历史源代码 ZIP。未执行 Git commit/push。

### 第六周代码复现交付的最终静态检查（2026-10-14）
- 新增只读 `week6/reproduction/qa_reproduction.py`：重新校验历史 ZIP SHA-256 与 344 个条目、Git 对象清单、自动执行的原代码建库/迁移/R01–R12/VFY01–VFY14 日志，以及源/副本字节相同的迁移前基准和迁移前后 3763 行业务对账。最终运行全部通过，记录为 `result/week6/reproduction/qa_reproduction.log`。
- PowerShell 新复现脚本语法解析检查 PASS，重新运行旧第五周、第六周与 v1.1 ER QA 全部 PASS。
- 文档核对过程中先检测到三条相对链接失效（本次新增的复现 SQL 相对路径一条、迁移归档前已移动的第五周目录两条），逐项修正链接而未改原正文含义；重新检查涉及的 Markdown 相对链接 **145 条 / 0 失效**。
- 实测复用已存在的 `-Suffix W6Auto261014` 时程序在开始前拒绝写入，符合“不覆盖已有目录/数据库”的安全要求。
- `git diff --check` 通过，出现 Windows CRLF/LF 行尾提醒但非失败；其它任务的未提交 `report/overview_modules.*` 和关联 README/ROADMAP 片段保留原状。原 v0.1/v1.0/v1.1 业务数据库未被复现脚本覆写。本轮**未 commit/push**。

## 2026-10-14：第六周当前工作交接文档（开始）

- **用户要求**：在 `D:\Desktop\DB\DB_lab\week6` 生成可由同事继续工作的上下文文件，并做本地 Git commit。
- **依据核对**：仓库最新已有提交 `5ec2c94`，此前依次为 `e82ce7b`、`43b5112`，迁移前基线 `c8d4e64`。本地 `main` 已有另一项 `report/overview_modules.*` 的 5 个未跟踪文件及 README/ROADMAP/AI 日志的未提交改动；本轮不得混入提交。
- **只读数据库核验**：`TokenHubDB_v01_A` 为 14 表/17 可信 FK/9 视图，`TokenHubDB_v10_W6_20261014` 为 15 表/18 FK/11 视图/99 个周期/3394 条汇总，`TokenHubDB_v11_Issues_20261014` 同样为 15 表/18 FK/11 视图，另有 13 个 v1.1 触发器、3 个受控存储过程。三库均处于 ONLINE。
- **拟写入文件**：`week6/HANDOFF_CONTEXT.md`，保留第五、六周详细文档原始结论，区分已完成的规范化及复现、v1.1 的前向保护、未解决的旧库数据异常及其他待做质量验收。完成后更新入口、检查链接/敏感字段和 Git diff，并仅提交交接相关差异。

### 交接文件已写入（2026-10-14）

- 新增 `week6/HANDOFF_CONTEXT.md`（152 行），涵盖项目和主要数据库位置、历史提交/完整旧代码 ZIP、P0–P5 规范化成果、R01–R12/VFY01–VFY14 两条数据来源差别、v1.1 I01–I10 已实施范围、尚未解决的历史数据/写入治理/独立评审/Ruff 与集成测试，以及给接手同事的操作和验收清单。
- `week6/README.md` 顶部新增交接入口，保留旧版报告按阶段留下的“当时状态”，不默改历史结论；`TokenHubDB_v01_A`、`TokenHubDB_v10_W6_20261014`、`TokenHubDB_v11_Issues_20261014` 均只进行元数据 SELECT，未执行写库操作。
- 交接文档内容源于已提交文件、现存结果日志及三库当前元数据（14/17/9、15/18/11、15/18/11 加 13 个触发器与 3 个过程），没有记录任何密钥或密码哈希值。

### 交接文档 QA（2026-10-14）

- `week6/HANDOFF_CONTEXT.md` 的相对链接 **37 条 / 0 失效**；仅引用项目里可查验的设计、回归、备份和复现结果。
- 依次重跑 `week6/reproduction/qa_reproduction.py`（历史 ZIP 344 文件/哈希、两段日志、3763 行业务对账）、`week6/qa_week6.py`（15 实体/18 FK/ER 图片/文档链接）、`week6/v11/qa_approved_rules.py`（v1.1 模型）以及 `week5/qa_week5.py`（14 实体/17 FK），全部 PASS。`git diff --check` 通过（仅有 Windows 文档行尾提示）。
- 这些 QA 为自动检查；**没有收到同事人工签收或独立审阅结果**，也未运行任何修改数据库的操作。待提交时采用精确暂存，保留其他任务的 README/ROADMAP/AI 日志改动及 `report/overview_modules.*` 未跟踪文件。

## 2026-10-17 第六周 v1.1 加固与历史数据修复

- **要求**：完善 v1.1、处理尚未闭环的业务约束与旧数据库异常、清理根目录 README 的过期状态；暂不修改第二阶段报告。
- **执行**：核对旧库 v0.1_A 的 20/402/225/1 四类异常；以固定种子生成器核对订单、订单明细、3000 条调用业务身份、库存和汇总后，仅在新建 TokenHubDB_v11_Harden261017B 副本进行合成数据校正。先备份并 CHECKSUM/VERIFYONLY，11 个用户注册时点、226 条调用时间或关联账号、2 个账号及相应库存流水、1 条合成异常引用被核对更正。旧 v0.1 及此前队友 sh 的 v1.1 未改。
- **约束与流程**：确认并规范 3000 条消费流水的调用引用；新增注册/provider/有效期反向保护、重要财务表直写限制、受控支付及补货；升级消费事务以写入明确的关联流水。
- **测试与失败处理**：首次使用 Python ODBC 运行备份/还原时连接没有等待服务端全部完成，产生一个 RESTORING 的自建测试库，已仅清理该失败测试库并改成 sqlcmd 阻塞等待；历史数据映射预检查和触发器回归首次遇到匹配集合/错误回滚顺序问题，修复后分别复测通过。最终 VFY01–VFY14、X01–X10、Y01–Y04 和原 v1.1 五组测试全部通过。
- **文件**：week6/v11/、result/week6/hardening/Harden261017B/、README.md、week6/README.md、week6/v11/README.md；原第二阶段 report/stage_report.md 没有改动。远端 sh 的正式 v1.1 尚未升级；退款完整账本属于后续开发边界。


## 2026-10-17 统一 v1.1 与退款开发

- **问题**：原第六周基础修复和加固分在两个目录，尚缺部分消费退款、金额责任流水、防重复退款。
- **实现**：合并到 `week6/v11`；加入 OrderTokenLots 和 RefundLedger 两表以及两条标识性 FK；逐明细记录发放、FIFO 消耗和收回，按未消费比例及原订单明细成交价格计算应退款额。每个订单退款唯一；事务内扣回 Token，现金应付款另行凭外部支付凭证结清。旧 refunded 合成订单保留，不伪造结算。
- **测试**：在备份的新库 `TokenHubDB_v11_Full261017D` 从原 v0.1 完整复现，旧问题修复与规范化 R01–R12、VFY01–VFY14、X01–X10、Y01–Y04、RF01–RF06 通过，17 表/20 FK ER 匹配。退款 100000 Token 使用 20000 后按 80000 返还对应 5.52 的应退金额；完全未使用的 100000 Token 返还 6.90 应退金额。所有验证交易回滚。历史异常在新副本为零，原库未更改。
- **限制**：无支付渠道可执行外部资金退款，数据库只能登记待支付金额和经服务端/人工验证的外部结算编号。第二阶段报告不修改；旧目录删除前先核对新路径不依赖它们。未执行 Git 提交。

## 2026-10-17 第六周退款缺口的人工发现与后续修复

-  在询问和核对 v1.1 的退款逻辑时，指出旧版主要只有订单 refunded 状态和相关明细约束，缺乏用户应退款金额、已消费 Token 的处理、退款流水及重复退款保护。随后明确要求补齐以上功能，并整合原先分散的两个 v1.1 代码目录。此处的“人工发现”指用户主动识别并提出功能缺口，不表示用户亲自执行了数据库测试。
- **发现依据**：原设计允许订单 status 为 refunded，合成样例里已有 2 条退款状态订单，但当时不存在按原成交价计算返款、扣回未用 Token、记录现金退款责任并防止重复退款的完整受控事务。仅修改订单状态不能证明用户余额与现金退款已经同步。
- **本轮采用的实现规则**：新增 OrderTokenLots 和 RefundLedger 两表及 2 条 PK/FK，已付款明细按购买顺序建立 Token 批次，消费按 FIFO 扣减。退款事务仅收回该订单未使用 Token，按订单明细成交小计乘以未消费比例、逐明细四舍五入计算应退款额；已消耗部分不退。每订单退款唯一，重复调用不重复扣减。应退款先记为 awaiting_transfer；外部支付实际成功且凭证经服务端/人工核实后才登记 settled。按未消费比例计算是本次系统采用的规则，不冒称其他组员已独立审批。
- **文件修改与清理**：合并基础修复与加固代码到 [week6/v11](../week6/v11/README.md)；新增 [退款结构](../sql/v11/07_refund_schema.sql)、[Token 批次账务](../sql/v11/08_accounting_lots.sql)、[退款事务](../sql/v11/09_refund_workflow.sql) 和 [退款测试](../sql/v11/10_refund_regression.sql)。原 week6/issue_fixes、week6/hardening 代码目录在独立重建通过后删除；历史测试日志和备份保留。
- **验证结果**：在新建的 TokenHubDB_v11_Full261017D 从 v0.1 备份、还原、迁移、修订可追溯的合成历史数据，再安装完整 v1.1 并运行 R01–R12、VFY01–VFY14、X01–X10、Y01–Y04 及 RF01–RF06，全部通过。退款案例中，原价 6.90 的 100000 Token 已使用 20000 时，只收回剩余 80000，记录应退 5.52；完全未使用时记录应退 6.90。重复退款、重复凭证及直接伪造退款流水的反例已测试。[退款回归日志](../result/week6/v11/Full261017D/final_validation/validation_10_refund_regression.sql.log) 和 [总体验证日志](../result/week6/v11/Full261017D/final_validation/validation_verify_v11_full.sql.log) 均保留；测试交易回滚。
- **未完成边界**：数据库不向用户直接转账，尚未接入支付渠道及验证实际资金到账；原 v0.1 和队友 sh 电脑的旧 v1.1 未更新；第二阶段报告暂不动。

## 2026-10-17 SQL 按 v0.1/v1.0/v1.1 分版本整理

- **用户问题与决定**：人工检查发现原 `sql/` 还是队友早期 v0.1 的建表和数据文件，要求按 `sql/v01`、`sql/v10`、`sql/v11` 整理；第六周目录保留分析、ER、数据字典和一键部署入口。保留迁移前基线，不把原 14 表脚本伪称最新版。
- **实际文件操作**：移走原 `sql/` 的 v0.1 建库、数据、约束、查询、签名等 10 个 SQL 文件及 README 到 `sql/v01/`；移动 `migration.sql` 和 `regression.sql` 至 `sql/v10/`；原 `week6/v11/` 的 23 个业务、迁移增量及验证 SQL 统一移入 `sql/v11/`，原目录保留 Python 入口、ER 图、数据字典及 README。新增三个版本入口说明和根 `sql/README.md`。
- **代码与引用**：更新 `tools/run_v01.ps1`、`tools/datagen.py`、`tests/test_sql_integration.py`、`week5/qa_week5.py`、`week6/reproduction/run_from_snapshot.ps1` 及 `week6/v11/` 的 SQL 文件读取路径；同步修复周次文档及相对链接。原归档 ZIP、其 344 文件清单和哈希不变；第二阶段报告仅把两条过时的 v0.1 SQL 链接改为新位置，没有修改正文。
- **v1.1 实际部署测试**：在本机新库 `TokenHubDB_v11_SqlTree261017A` 从未修改的 `TokenHubDB_v01_A` COPY_ONLY + CHECKSUM 备份并校验、执行 v1.0 迁移、原 v1.1 规则、固定种子合成历史核对、账务保护及退款。17 表、20 个可信 FK，R01–R12、VFY01–VFY14、X01–X10、Y01–Y04、RF01–RF06 全部通过；历史异常在新副本 20/402/225/1 → 0/0/0/0。证据位置：`result/week6/v11/SqlTree261017A/`。
- **v0.1 签名失败与修正**：首次独立运行源 SQL 及 VFY 均通过，但 Windows PowerShell 在捕获 `sqlcmd` 14 行签名时读取为 0 行；改用 `sqlcmd -o` 原始 UTF-8 文件后仍遇到相同问题，两个失败用例及原始输出保留在 `result/sqltree_v01_261017*`。人工核对原始 SQL 输出确实有 14 行有效签名；新增 `tools/signature_from_log.py` 直接按 UTF-8 字节解析并验证 14 张预期表、输出 UTF-8 BOM + LF 格式。重新从头建 `TokenHubDB_v01_SqlDir261017C`，DDL/样例/CRUD/视图/查询/约束/权限/VFY/签名全部通过，结果 `result/sqltree_v01_261017c/`。
- **历史独立复现**：新后缀 `SqlReorg261017A` 成功从未改动的第六周前 344 文件 ZIP 创建 v0.1 → 从 `sql/v10` 迁移到新副本 → R01–R12 / VFY01–VFY14 全部 PASS；迁移前后 3763 行非权限业务记录零差异。证据 `result/week6/reproduction/SqlReorg261017A/`。
- **验收和边界**：第五周/第六周/v1.1 的 ER QA、历史归档 QA、Python AST 和 `git diff --check` 通过；遍历约 450 处非归档 Markdown 链接，修复 `week6/reproduction/README.md` 的一条旧 `issue_fixes` 链接后 0 失效。新数据库均为隔离测试库，原 v0.1、旧 v1.0/v1.1 未覆盖；未执行 Git commit/push。支付平台实际退款仍未接入，数据库只记录应退金额和外部确认凭证。

- **补充单元测试**：`python -B -m unittest discover -s tests -v` 共 22 项，其中 12 PASS、10 因未设置独立 SQL 集成测试库而 skipped；没有把 skipped 记录为通过。独立 SQL Server 建库、规范化迁移及 v1.1 退款验证另以上述实际执行结果为准。

## 2026-10-21 第7–9周 Web 应用开始

用户要求实施已审核计划，采用 Flask/Jinja/pyodbc、三角色和调用时扣库存。原工作区已有修改，保留；桌面工作树工具返回 Not a git repository，使用 Git 创建独立工作树 DB_lab_webapp，未提交或推送。先增加 HTTP 边界反例，执行 `python -m unittest discover -s tests -p test_webapp.py -v` 退出码 1（缺少 webapp 模块，预期的实现前失败）。数据库与普通账户配置尚未执行；后续将记录实际结果。

### 第7–9周 首批边界实现

已新增 webapp 的 HTTP 边界测试及 Flask/服务/DAO 分层实现。数据库任务的源文件反例因 sql/app/install.sql 尚不存在而失败（预期红灯），数据库集成测试未执行。独立工作树 venv 已安装 Flask、pyodbc、bcrypt、waitress、ruff；旧 Python 基线中 12 项通过，10 项数据库测试因未指定库 skipped，新增 Web 模块缺失反例曾失败，不能登记全量通过。接下来补齐页面、部署与数据库后统一运行。

### 第7–9周 SQL 应用层文件完成

sql/app/install.sql 已实现 26 类 JSON 业务操作、五个会话/入口授权及 owner 事务封装；tests/test_app_sql.py 源文件检查通过，两个数据库测试尚未设置库而 skipped。静态 Ruff/格式与 diff 检查通过（数据库编译与实际执行尚未验证）。本轮另扩展新建 Web 源库的备份还原，静态编译发现 Python 引号错误，已按准确行修正，待重测。

### 第7–9周 首轮数据库基线失败与根因

Web261021A 的全新 v0.1 建库及全部验证通过，备份、还原、v1.0 迁移和五组 v1.1 基础测试通过；旧 regression_v11.sql 仍跨库硬编码读取 TokenHubDB_v01_A，导致新干净源库与历史旧库误比较而报 51707。按 systematic-debugging 检查报错日志及 R03 查询后，已在准备工具运行时替换跨库源引用；不改旧回归文件、不覆盖 A 的失败证据，下一轮使用 Web261021B。当前未声称最终应用或数据库验收通过。

### 第7–9周 HTTP 测试通过与第二轮环境修复

Flask 路由同一操作的 POST/PUT 入口原使用相同 endpoint 引发覆盖异常；按错误定位改成每条路由唯一 endpoint。HTTP 边界测试现 5 项通过，包含 CSRF 在连接前拒绝、连接失败脱敏和 JSON 404。Web261021B 已通过 v0.1→v1.0→基础 v1.1 回归及加固；退款准备子进程硬编码 python，调用了不含 pyodbc 的系统解释器，修正为 sys.executable，保留失败日志并使用新后缀 C 重建。尚未运行最终 Web 集成验收。

### 第7–9周 页面与事务适配

已新增中文工作台、三角色导航、商品/订单/明细/库存/补货/调用/退款表单，原生 JS 语法检查通过。HTTP 五项边界测试通过；新增九项 API 集成测试尚待数据库。SQL 应用层追加独立适配脚本，为七个旧交易过程保留默认返回行为并增加关闭结果集及输出编号参数，避免 INSERT EXEC 阻止旧 CATCH 回滚。退款外部凭证唯一性改为非空过滤索引以支持多笔待结算退款；SQL 共十项测试已定义，源检查通过，数据库测试尚待 C。金额与 Token 出口转换成字符串。

### 第7–9周 首次 Web 审查与修正

独立审查发现商品选择只取第一页、价格表单 min=1、BIGINT 安全阈值出口未转字符串、异步栏目请求可能串页及 Python 层缺少显式归属比较。已逐项修正：加载完整在售目录、价格最小0.01、阈值保持字符串、列表使用请求序号丢弃旧响应、服务层读取订单后比较会话顾客；SQL 仍在事务中再次验证。所有公共按钮执行期间禁用并保留错误提示回退，避免重复提交或弹窗未挂载时丢失错误。尚待浏览器与集成测试确认。

### 第7–9周 SQL 实测通过与 ODBC 会话修复

C 应用 SQL 经 SET 选项和保留字 app.[Execute] 编译修正后安装成功，11项 SQL 实测通过（08_app_sql_tests.log），覆盖18表各4项DML拒绝、DDL/旧过程拒绝、会话、归属、事务、精确消耗和多退款。API 首测9项在登录连接复用时报 HY000；单独数据库调用成功，跟踪到预览 EXECUTE AS 上下文未 REVERT 与 ODBC 池重置冲突，连接进入596终止状态。已禁用池化并在预览连接关闭前 REVERT，下一轮实际重测；未将首轮API失败计作通过。

### 第7–9周 API 实测通过

修复连接池上下文后，九项 Flask→服务→DAO→SQL 的集成测试全部通过（09_api_second.log），包含购买/调用/退款/结算、空单支付拒绝、跨顾客和角色越权、注入/非法输入、注销旧会话拒绝、订单明细第二步失败整笔回滚、并发支付仅一笔成功及数值字符串。测试连接实际降至 app_runtime_probe 数据库用户，不等于普通 Windows 账户启动验收。下一步浏览器流程及全新 D 后缀一键复现。

### 第7–9周 全新一键重建与浏览器纠偏

Web261021D 从新源库到最终应用准备全链路一次执行成功（result/webapp/Web261021D/，manifest.json），未修改旧数据库。浏览器已完成顾客登录、下单和支付；调用选择框因隐式label包含option文本导致自动化精确标签定位失败，已为字段设置明确aria-label并保留失败回执。此前登录select只读type错误也已修正。部署审查发现数字SID缺*及PowerShell5.1不支持静态随机数重载，已改成数字SID标准写法及兼容RNG.Create；未执行账户创建。

### 第7–9周 故障注入与锁竞争验证

新增五项故障/并发测试，C首轮四项受pyodbc隐式事务计数断言影响（12_app_faults.log）；改用表级行数及业务校验和、触发器/临时样例消失验证回滚，C五项通过（13_app_faults_retry.log）。随后在D五项全部通过（05_fault_tests.log），分别在支付、消费、补货、退款后段注入55971；18表基准恢复。另一项观察到LCK等待，退款和消费事务回滚后基准一致。D先前全量49项通过，新增后需最终54项全跑。普通账户启动脚本加入以该身份运行的runtime_identity前置检查，仍待实际管理员启动步骤。

### 第7–9周 浏览器通过与图示检查

C三角色完整浏览器流程通过（18_browser_fourth.json）：顾客购买/支付/调用/退款、店员权限与补货、管理员0.50元商品新增及SIM结算。先前第二轮曾完成写入后被关闭弹窗重复刷新清除提示，第三轮因复用测试商品联合唯一键而冲突；已去掉重复刷新并采用唯一Token档位，失败回执全部保留。桌面与390px窄屏截图已目视，窄屏表格内部滚动无页面横向溢出，随后改善窄屏主操作按钮换行。完整18实体22FK Mermaid/SVG/PNG及渲染脚本已生成并目视。图路由首次左边界不可达，改用右侧/顶部入口后通过，未改变基数与关系。登录结构化kind参数增加400反例，避免输入列表触发500。

### 第7–9周 最终独立审查

SQL与应用整体静态审查确认未发现其它P1/P2；唯一P2为断线后rollback/REVERT异常覆盖原503。新增test_disconnect_cleanup_does_not_mask_service_unavailable，先观测500失败再改为逐项尽力清理，HTTP7项通过；独立复查已认可修复。日志改为SQLSTATE和数字native_codes，不保存任意异常文本。SQL24种公共操作，纠正早期26统计误差。准备将通过核对的新增文件合回原DB_lab；对已修改的README/ROADMAP/AI文档仅追加本轮内容，保留用户原差异。普通Windows账户实际部署与组员复现仍未执行。

### 第7–9周 合回原目录

本轮文件已合回DB_lab：新增214文件、更新10个既有文件，原先9项已改文件的字节前缀/完整内容核对保留，清单见result/webapp/integration_manifest.json。首次合并预检因Git LF与工作区CRLF原始字节差异拒绝，未写文件；改成代码文本归一化比较且对用户既有改动仍按字节保存后通过。格式终检发现既有签名解析器一项排版不符，已只调整格式，无行为变更。原目录venv安装命令在合并完成前先读requirements-web.txt而失败，随后的07测试因此缺pyodbc失败，日志保留；现重新安装后再执行，不以07失败记录作最终结果。

### 第7–9周 原目录最终验收

DB_lab原目录重新安装依赖后，08_original_final_tests.log记录56项全部通过、无skipped、退出码0；包括原22、SQL11、故障/并发5、HTTP业务11、HTTP边界7。Ruff check webapp tools tests report/render_app_er.py通过，format --check为21文件已格式化；JS语法、两份PowerShell解析、git diff --check均通过。144条本地文档链接核对无失效；D实际18表22可信外键，负余额和超额批次均0。运行预览已改为原DB_lab代码和D库，预览连接先EXECUTE AS app_runtime_probe；尚不是普通Windows账户最终部署。原改动保留清单已核对。样例密码保存在忽略的instance中未写入日志，未commit/push。

### 第7–9周 原目录浏览器交付核对

原目录代码连接D库的三角色完整流程通过，回执09_original_browser.json，七段业务全部PASS；服务监听127.0.0.1:5050，保留本地预览供用户核对。阶段报告、手册、数据字典、图源/导出、AI记录、分工待办及证据索引已同步。无commit/push。最终未完成项仅外部权限步骤和组员核对：本地普通Windows运行账户需管理员执行setup_web_runtime.ps1，并由计划任务自动运行runtime_identity.py证明实际身份；当前会话无管理员组权限，未执行该动作，不冒称已部署完成。

## 2026-10-21 按用户要求仅保留原项目

用户要求不另建DB_lab_webapp，全部直接在D:\Desktop\DB\DB_lab修改。核对临时工作树224个变更/新增文件，原目录无缺失；6份共享文档的本轮追加均已保留，9份差异属于原有内容、后续验收记录和原目录的配置校验增强。两个临时运行日志保存至result/webapp/temporary_workspace_logs，私有样例配置已在原目录保留且未写日志。确认Web进程来自原目录后，删除临时Git工作树及无独有提交的临时分支，DB_lab_webapp路径已不存在。AGENT.md记录今后直接在原目录开发，不再默认创建副本/工作树。本轮不改业务代码、数据库或既有测试结果，未commit/push。


## 2026-10-21 按用户授权分步提交

用户明确要求每一步修改分别commit；只创建本地提交，不push。提交前Ruff检查与21文件格式检查通过、diff检查通过，样例私有密码未出现在提交候选文件。沿用此前56项测试及浏览器通过证据，本轮不改业务。先独立提交原先已暂存的业务总览，并仅暂存README对应说明段，保留其它README改动供后续提交。

- 331b9a4：业务总览HTML、可编辑图源、渲染脚本和图像，附对应README说明。

- b626ac8：新源库白名单、实际逻辑文件还原、回归来源替换、sys.executable及签名工具格式；提交成功，未push。

- 485811e：会话身份、24种受控业务操作、窄权限及旧事务兼容适配；提交前检查发现SQL文件末尾多余空行，已仅去掉尾空白并检查通过，未改SQL语义；提交成功，未push。


- 61bd777：Flask路由、认证/CSRF、业务校验、参数化DAO、异常/连接清理和依赖配置；提交成功，未push。

- dd3d6f1：三角色工作台、表单/分页、交易页面、状态反馈及窄屏布局；提交成功，未push。

- 7f823f4：从空库准备、普通Windows账户部署及身份核验、浏览器测试工具；提交成功，未push。

- 06857e0：SQL权限/会话、四类故障回滚、并发支付/消费/退款及HTTP边界回归；提交成功，未push。

- eb8e652：18实体22外键可编辑源、数据字典和图像；SVG行尾空白已清理，XML及规范化绘图属性逐项等价检查通过，导出脚本同步去尾空白；Ruff通过，提交成功，未push。


- a92ffb5：分轮失败/成功日志、全新D复现、56项测试、浏览器回执与截图、原改动保留清单；提交成功，未push。

- 878962c：记录用户仅在原DB_lab开发的约定，临时工作树与分支此前已清理；提交成功，未push。

### 分步提交收尾

已按业务总览、数据库工具修复、SQL应用事务、Flask后端、角色界面、部署工具、测试、ER模型、验证证据、原目录协作约定分别完成10个本地提交；以上逐项记录给出实际短提交号。当前收尾提交保存README、任务映射、操作手册、阶段报告、执行计划、分工及本轮AI/ROADMAP记录。旧日志中“未commit/push”描述其记录时点，本轮提交由用户明确授权；未执行push。提交不重演中间失败版本，也不改写已有历史。原有56项测试和三角色浏览器通过证据保留，提交期间仅清理SQL/SVG尾空白及同步导出规则，SVG结构/绘图属性等价检查通过。

## 2026-10-21 README全角色人工验收流程

用户要求生成用于人工检验实现效果的流程，涵盖所有角色职责并写入README。依据webapp/static/app.js的实际导航/按钮、services.py的24项操作权限、路由及sql/app/install.sql的库存选择/FIFO/退款规则，在README追加游客、管理员准备、顾客订单与明细、支付调用及三类退款、第二顾客隔离、店员运营、管理员继承职责/维护删除/结算、手动API反例和结束记录表。当前用户已明确要求操作流程，因此本次按该要求增加操作步骤。

采用全新实验库Other账本为零的前提，P价12、下单后目录改15，旧单两份仍按12成交；消费50000后回收150000，对应应退18.00。明确调用按合格账号编号选择，不默认消耗新建账号；补货计划与实际量分开，管理员结算凭证由服务端生成。没有提供密码值、没有新增功能或修改数据库，没有将流程撰写登记为组员已人工执行。

验证：AST提取ALLOWED与README覆盖表比对，24项全部覆盖；README本地链接无失效；JavaScript辅助函数经node --check通过；金额及Token算例程序核对通过；git diff --check通过。未重跑数据库/浏览器交易（本轮仅文档），人工记录保留待填写。按用户此前要求，此文档及对应AI/ROADMAP记录单独本地commit，不push。

## 2026-10-28 补齐人工验收前后的服务器启停

用户指出README人工流程缺少验收前启动服务器、验收后关闭服务器。已对照webapp/__main__.py、tools/run_web.ps1与setup_web_runtime.ps1，在README第0节增加原目录/依赖/SQL服务/端口检查、前台开发预览启动、已有普通账户计划任务启动、首页及商品接口就绪检查；第9节增加原启动终端Ctrl+C退出、计划任务禁用和停止、确认5050监听释放及保留数据记录。明确二选一、不能重复占端口、关闭浏览器不等于关闭服务器、不停止SQL Server、不批量结束Python、不重复运行建库或账户安装脚本。

预览启动允许选择已有库，但精确数值验收仍要求干净Other账本；普通账户任务读取其本地配置，不能靠管理员终端环境变量切换目标库。没有读取或输出密码、密钥及运行配置内容。首次静态检查命令中正则被PowerShell解释，改为UTF-8独立脚本后重新检查通过。

验证：README全部11段PowerShell只经Parser.ParseInput解析，语法通过；本地链接检查无失效；保留变量赋值检查及启停章节检查通过；git diff --check通过。本轮仅文档修改，未运行所列服务/任务启停命令、未改变当前应用/SQL服务状态，未将文档预期写为人工执行结果。按用户分步commit要求单独提交，不push。

## 2026-10-28 运行中验收（部分）

根据用户要求通过本地服务的 Edge 页面实际操作，结果与编号记录在 result/webapp/README.md。覆盖游客搜索空状态、错误密码和三角色登录、管理员商品与账号新增、店员补货、顾客订单明细和支付调用、部分退款与管理员模拟结算；尚未检查完整权限、幂等、隔离及所有异常路径，未保存截图或进行独立 SQL 对账。没有关闭服务器，没有清理验收数据。

## 2026-10-28 补做运行中验收

执行当前服务 HTTP 请求并断言角色、状态和业务结果，涉及订单 163–170、补货 21–22、临时商品 67 和账号 64；其中 164、67、64 按验收流程删除，其余交易记录保留。并发支付、并发消费、退款竞争各验证两次请求状态及相关余额。浏览器核对账号 17 减少 150000、账号 63 为 1011000。结果、限制见 result/webapp/README.md；未采集原始日志或截图，不声称中途故障注入、分页及受限 Windows 账户通过。

## 2026-10-28 持续验收

当前库通过订单 170 定位为 TokenHubDB_v11_Web261021D。运行 tests.test_app_faults（5 项）及 tests.test_app_sql（11 项）均退出 0；两页商品分页实测后删除本轮临时商品 84–90。逐事件读取 3199 条余额事件，未发现负余额或最终余额差异。库存与流水全量检查发现五项差异，比较 Web261021C、D 与创建代码后定位为应用账号初始额度无期初流水；记录在 result/webapp/README.md，未修改历史数据。运行账户检查发现 TokenHubWeb 存在，服务属 dulant，受保护文件及任务查询被拒；未以此推断任务不存在或声称受限 Windows 账户通过。

## 2026-10-28 修复期初库存差额

先新增SQL回归，观察新账号无期初行（0 != 1）失败；新增共享触发器、期初唯一索引及受控删除例外，安装入口包含共享SQL，覆盖seed和Web入口。修复工具仅接受Web库和匹配的人工核实清单，拒绝非批准差额，完整消费备份与校验结果集后再迁移；失败过程提取/备份尝试及事务回滚已在证据README记录。

当前库追加5笔后全量账号/库存/流水对账通过；重跑迁移待补记0。20项针对性检查退出0；全量unittest60项、skipped21；ruff check tools tests webapp通过。仓库全目录扫描20项旧格式问题未改动。详见result/webapp/opening_inventory_20261028/。数据库备份保存在SQL备份目录，不提交凭据或备份文件。


## 2026-10-28 第7—9周 Web 顾客自助注册补全

- **人工发现**：用户在网站测试中指出只有预置演示账户，缺少新顾客注册入口；课程主要要求登录，注册作为完整业务流程的补充。
- **代码实现**：新增 `sql/app/register.sql` 中的 `app.RegisterCustomer`，仅创建普通顾客；过程采用 `WITH EXECUTE AS OWNER`、仅授权 `app_runtime` 执行，并并入 `sql/app/install.sql` 的新库自动安装流程。参数化 SQL、用户名/邮箱唯一性、bcrypt 密码哈希和 CSRF 由原分层机制及新增校验共同保证；不能通过传入角色字段创建员工或管理员。`webapp/services.py`、`webapp/dao.py`、`webapp/__init__.py`、`webapp/static/app.js` 均增加注册能力，成功后自动登录。
- **文档同步**：更新 Web 使用说明、增量数据字典和阶段报告；根目录 README 增加 G2a 注册人工测试。演示环境未实现邮箱验证、验证码、密码找回或公网流量限制。
- **真实验证**：全新隔离数据库 `TokenHubDB_v11_WebSign28A` 从 v0.1→v1.0→v1.1→Web 完整安装成功，66 项自动测试全部 PASS（0 failed、0 skipped），含新注册、登录、重复账号与邮箱、弱密码、CSRF 和权限拒绝测试。证据为 `result/webapp/WebSign28A/registration_unit_stderr.log`。
- **边界**：本次只在当前本机 Web 实验数据库部署新增注册过程，没有修改原始库；实际浏览器人工注册仍需用户操作确认，AI 自动测试不冒充人工复核。本轮未执行 Git commit/push。

## 2026-10-28：第二阶段最终交付整理与真实 Edge 证据

- **用户明确要求**：第1—4周混入当前 README 和相关目录的历史内容集中归档至 `archive/`，以第5—9周为当前交付主线；最终确认 `report/render_app_er.py` 与 `report/render_overview_modules.py` 保留，不删除可编辑图源和渲染器。
- **实际执行**：生成 `archive/stage1_to_stage2_manifest.json`，移动第一阶段报告、旧角色说明、旧复现说明、旧计划、旧需求和旧截图/SQL 证据；混合历史 README、ROADMAP、AGENT、AI 日志与组员分工原文完整复制到归档后，再将当前文件改为第二阶段版本。保留第5—9周建库必需的 `sql/v01/` 及工具。
- **浏览器执行**：在独立 `TokenHubDB_v11_WebStage2A02` 完整新库上，Edge/Playwright 真实访问运行中的 Flask，完成注册、唯一性拒绝、错误密码、管理员建商品/上游账户、顾客下单和模拟支付、Token 调用、部分退款/幂等、第二顾客越权拒绝、店员补货/越权、管理员模拟结算及游客 401；22 张 PNG 与哈希、42 条事件和 request_id 存于 `result/stage2/WebStage2A02/browser/`。初次 `WebStage2A01` 浏览器脚本遇到自动化断言定位不当而中止，失败现场与日志保留；修正等待控件定位后**换新数据库后缀**完成整条流程。
- **数据核对**：独立只读 `tools/stage2_reconcile.py` 核对 25 项业务值及 22 张 PNG SHA-256，全部 PASS。订单 #112 金额 12.00 元、135791 Token；消费 50000，回收 85791，应退 7.58，最终余额为0；自动上游选择使实际扣费发生在账号 #17，新增账号 #18 仅初始入库与补货8000，均以各账号真实流水对账。脚本最初将新账号误认为消费账号，断言失败后从真实 TokenUsageLogs 确认账号 #17，纠正验证而非修改业务数据，保留故障事实。
- **相关测试**：此前独立新库 `WebSign28A` 运行 66 项 unittest 全部 PASS（0 failed、0 skipped），与本次 Edge 及 SQL 实测明确区分。用户亲自再次操作、第二名组员签收、真正普通 Windows 账户部署以及真实外部支付/调用均**未验收**。
- **文档更新**：根 README 由第一阶段混合口径变更为第5—9周总览、目录和复现入口；第二阶段报告增加实测截图、正常/异常 HTTP 及数据库前后对账、规范化分析、复现边界；分工按用户明确要求记第7周数据库基础代码为**陈诗翰**、第8周注册、测试和交付整理为**阮依成**，不将 AI 运行冒充组员签收。
- **Git**：保留本地工作区变动，未 commit、未 push、未覆盖用户已存在的实验库。


## 2026-10-28 两名组员验收及注册缺口记录更正

陈诗翰是第一名测试组员，先在自己的环境测试（据第二名组员阮依成确认）。阮依成是第二名测试组员，亲自访问5050网站核对顾客登录、店员/管理员订单和pending状态，发现缺少普通顾客自助注册，并要求补齐注册表单、后端鉴权、唯一性和权限测试。不能再把第二名组员网站验收记作未完成。66项unittest和22张Edge页面截图为AI辅助的补充自动化检查，与阮依成本人的操作范围分别记载。另一个全新Windows系统从零安装建库和正式受限账户启动属于附加待验事项。

## 2026-10-28 结果清理和验收归属修正

用户指出当前result存在大量重复且无必要的日志，明确授权清理无用旧结果，但要求保留有效测试与第5—9周交付链。先枚举各层文件/空间，建立25项精确清单、检查代码和Markdown引用；更新result/webapp/README.md及tests/README.md后再次检查，确认待处理文件没有活动Markdown直接链接。执行精确删除22个旧目录，归档第一阶段recheck及两个早期失败v0.1结果目录，合计373文件约13.5MiB。清单位置archive/evidence/stage1-legacy/stage2_result_cleanup_20261028.json；保留当前WebManualA01、陈诗翰先行Web261021D、66项测试WebSign28A、22张截图WebStage2A02、第5周证据及第6周迁移回归。仅本地文件整理，不触及SQL Server现存数据库或5050服务。

用户确认陈诗翰是第一名测试组员，在他自己的环境测试；阮依成是第二名测试组员且亲自进行了登录与订单可见性验收，其实测发现注册缺失并要求补齐。更新分工、README、ROADMAP、阶段报告和AI使用文档，第二名组员验收状态改为已参与、已完成相应网站实测，自动化全流程另列。避免把未亲手执行的22张自动截图误写为成员手工截图或编造陈诗翰的具体现场证据。

原agent.md经archive/coursework/week4/agent_combined_before_stage2.md恢复，SHA-256两者一致为D63F52BD6E704491FD875BD0F42257CF032FAB6A89E259B0EAC700916B7E86AE；当前git diff中不再修改agent.md。检查后端统一异常边界、SQL错误安全归类、请求编号日志与前端友好提示，机制原本已存在，不另行改动业务代码。
