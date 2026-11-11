# DB_lab 第六周工作交接上下文

> 更新日期：2026-10-14。供接手同事直接从现有提交、脚本、数据库和证据继续工作。本文记录已执行状态，不替代源 SQL、测试日志或独立人工复核。

## 0. 先读结论

- **第六周课程主任务已实施且能够独立重跑**：从第六周前的完整 Git 代码快照重新创建 v0.1，备份还原到另一数据库，执行周期规范化 `migration.sql`，再运行 R01–R12 与 VFY01–VFY14；两轮全新重建验证通过，非权限业务基准 3,763 行零差异。
- **不能写“所有现有数据库都通过 VFY”**：较早的本地 `TokenHubDB_v01_A` 本来就存在历史业务数据异常；其迁移副本继承这些异常。重新生成的**标准样例库**通过全套 VFY，不等于旧库数据已修复。
- **第五周 I01–I10 的后续改进只在 v1.1 隔离副本进行**：I02/I03/I04/I07 的业务口径已由用户确认并落地；I01/I05/I06/I08/I09 有范围有限的前向约束与事务过程，但其他写入路径和旧数据问题仍存在。
- **接手的核心工作**：确认最终课程材料/人员审核；评估旧数据如何按可信原始依据修复；收敛 v1.1 的直接写表入口并添加全路径测试；完善 Python 环境、Ruff 和集成测试；如果需一次性重放 v1.1，另做可复现部署链。
- **版本边界**：本交接写入前本地 `main` HEAD=`5ec2c94`。提交历史与当前工作区状态以接手时 `git log`、`git status` 为准。此交接文件的 Git commit 记录在交接之后产生；**同事人工签收/独立复核未发生，不得标成已完成**。

## 1. 机器、环境和仓库入口

| 项目 | 当前核对信息 |
|---|---|
| 工作电脑 | sh，Windows `LAPTOP-3H5FCR3B` |
| 主仓库 | `D:\Desktop\DB\DB_lab`，Git 分支 `main` |
| SQL Server | `localhost\SQLEXPRESS`，SQLCMD 使用 `-E -C`（Windows 集成连接） |
| 正式项目代码 | `sql/`（DDL、查询、迁移、回归）、`tools/`（v0.1 建库、数据生成）、`tests/` |
| 主要报告和证据 | `week5/`、`week6/`、`result/week6/`、`docs/`、`plan/` |
| 项目协作规范 | [`AGENT.md`](../AGENT.md)：包含数据库保护、审计留痕、Python 检查和 AI 使用记录要求 |
| 单位时间/权限 | SQL `DATETIME2` 以项目设定 Asia/Shanghai 为准；用户同意过**隔离副本**操作，不等于允许改动旧正式库 |

**不要使用** `-DropExisting`；不覆盖/删除旧数据库、SQL Server 备份、迁移日志或代码 ZIP。未得到新的明确授权，不要写入 `TokenHubDB_v01_A` 或重放迁移到已经迁移的数据库。不要读取或提交 `api_key`、密码哈希、凭据等字段值。SQL Server 的 `.bak` 在服务端备份目录，未纳入 Git。

### 已有数据库（本次交接只读核实，均 ONLINE）

| 数据库 | 用途 | 结构/状态 |
|---|---|---|
| `TokenHubDB_v01_A` | 较早的本地 v0.1 数据 | 14 表 / 17 个启用可信 FK / **9** 视图，保留历史问题 |
| `TokenHubDB_v10_W6_20261014` | 从上面数据库还原并做第六周迁移 | 15 表 / 18 FK / 11 视图；99 种周期，3394 条汇总；继承旧数据问题 |
| `TokenHubDB_v11_Issues_20261014` | 从 v1.0 再隔离出来，实施第五周业务规则改进 | 15 表 / 18 FK / 11 视图；13 个 `trg_W5_*` 触发器、3 个 `usp_W5_*` 过程 |
| `TokenHubDB_v01_W6Replay261014` / `TokenHubDB_v10_W6Replay261014` | 第一次从旧代码 ZIP 手动复现的一对库 | 原始 v0.1 → 已迁移 v1.0；全套验证通过 |
| `TokenHubDB_v01_W6Auto261014` / `TokenHubDB_v10_W6Auto261014` | 第二次从旧代码 ZIP **一键复现**的一对库 | R01–R12、VFY01–VFY14 全部通过 |

`DB_lab_replay_c8d4e64`、`DB_lab_replay_W6Auto261014` 是仓库旁边的两份**临时解压工作目录**，不是两个不同版本。权威旧代码备份是下述 ZIP；新建/删掉文件夹不会自动建库/删库。

## 2. Git 历史、代码备份与已冻结的交付物

| Git 提交 | 含义 |
|---|---|
| `c8d4e64` | **第六周开始之前**最后一个提交（2026-10-10），旧版代码备份源 |
| `43b5112` | 第六周 P0–P2：基线、函数依赖、规范化设计 |
| `e82ce7b` | v1.0 周期迁移、v1.1 第五周约束与回归等 |
| `5ec2c94` | 第六周前完整代码 ZIP、一键复现、两轮测试证据 |

**迁移前完整代码 ZIP**：[`archive/week6-pre-migration/DB_lab_pre_week6_c8d4e64_full_source.zip`](../archive/week6-pre-migration/DB_lab_pre_week6_c8d4e64_full_source.zip)

- 344 个当时 **Git 已跟踪**的项目文件，大小 5,237,257 字节；包括建库/样例/约束、SQL、Python、PowerShell、第五周 ER 和文档，不是当前代码的复制品。
- SHA-256：`D2DFA2F23504050ACBA3F4BDE95A7946DCA72D29F6599A6D75A67C16DDE5743C`。
- 清单：[`archive/week6-pre-migration/source_manifest.txt`](../archive/week6-pre-migration/source_manifest.txt)；说明：[`archive/week6-pre-migration/README.md`](../archive/week6-pre-migration/README.md)。
- **不包含**未跟踪文件、`.git` 完整历史、数据库数据文件/备份、登录凭据。请不要覆盖这个 ZIP 或公开发布前跳过内容审查。

## 3. 第六周主体实现：P0–P5 的实际情况

| 阶段 | 已完成内容 | 证据入口 |
|---|---|---|
| P0 | v0.1 备份与 CHECKSUM/VERIFYONLY，还原隔离副本；迁移前源/副本基准一致 | [基线证据](../result/week6/README.md) |
| P1 | 逐表分析原 14 表的候选码、FD、1NF/2NF/3NF、三种更新异常 | [依赖与范式](dependency_normalization.md) |
| P2 | 基于固定统计周期 FD 制定小范围分解、无损连接和依赖保持，保留其它必要业务快照 | [重构决策](redesign_decisions.md) |
| P3 | 实施 `UsageSummary → UsagePeriod + UsageSummaryCore`，恢复旧名的**查询兼容视图**；99 周期/3394 汇总；无数据丢失 | [迁移 SQL](../sql/v10/migration.sql)、[数据字典](data_dictionary_v10.md) |
| P4 | 订单明细/销售/库存/余额/用量、约束、正反例、角色权限及基准比较 | [回归 SQL](../sql/v10/regression.sql)、[回归日志](../result/week6/regression/regression_run_02.log) |
| P5 | ER 可编辑源/渲染、SVG/PNG、字典、README、报告和 AI 记录 | [第六周入口](README.md)、[报告材料](report_material.md)、[v1.0 ER](er_diagram_v10.mmd) |

核心 FD：对于当前**统一统计周期**规则，`(period_type, period_start) → period_end`；原 `UsageSummary` 的四元业务候选码包含这两个属性，因此原表存在部分依赖。拆分后 `UsagePeriod` 以 `(period_type,period_start)` 为主码，`UsageSummaryCore` 使用这两列构成可信复合 FK。连接交集决定周期表，因而能够无损恢复旧 10 列。

`dbo.UsageSummary` 在 v1.0 **是视图，不是物理表**：旧 SELECT 可用，但旧的 INSERT / `IDENTITY_INSERT` 不再可用。新数据写入需要先有 `UsagePeriod` 再写 `UsageSummaryCore`。旧版 `sql/v01/02_insert_data.sql` 仍属于 v0.1，不应直接用于 v1.0 初始化。

**版本差异**：旧本地 `v01_A` 有 9 个视图且部分视图字段不完整；由 `c8d4e64` 快照重新创建的标准 v0.1 是 10 个视图。最新 `sql/v10/migration.sql` 只接受这两种**已核实**的基线并按条件补齐缺失视图，不接受任意不匹配的结构。

## 4. 从零复现迁移（建议接手者首先做只读 QA）

完整说明：[reproduction/README.md](reproduction/README.md)，自动脚本：[reproduction/run_from_snapshot.ps1](reproduction/run_from_snapshot.ps1)，实测证据：[result/week6/reproduction/README.md](../result/week6/reproduction/README.md)。

在主仓库根目录先执行**只读**检查：

```powershell
cd D:\Desktop\DB\DB_lab
git status --short
git log -4 --oneline
python -B .\week6\reproduction\qa_reproduction.py
python -B .\week6\qa_week6.py
python -B .\week6\issue_fixes\qa_approved_rules.py
python -B .\week5\qa_week5.py
```

只有在确认可以创建**新的隔离数据库**后，才运行一键复现（示例后缀必须换成从未用过的 6–16 位字母数字串）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\week6\reproduction\run_from_snapshot.ps1 -Server 'localhost\SQLEXPRESS' -Suffix 'W6TeamReplay01'
```

脚本做：校验 ZIP 哈希 → 解压全部 344 文件到仓库外新目录 → 使用旧代码 `tools/run_v01.ps1` 新建 v0.1 → COPY_ONLY + CHECKSUM 备份及 VERIFYONLY → 还原另一个新库 → 迁移 v1.0 → R01–R12 → VFY01–VFY14 → 对比非权限业务基准；每阶段有明确日志，库/文件/目录若已占用则拒绝覆盖。**此命令确实会创建数据库和备份文件，不能当作只读检查。**

已完成的自动复现证据：[`W6Auto261014/replay_manifest.txt`](../result/week6/reproduction/W6Auto261014/replay_manifest.txt)；R01–R12、VFY01–VFY14 全部 PASS，迁移前后 **3763 条**非权限业务基准零差异。第一次分步复现同样 PASS。两次复现使用**从旧代码重新生成的标准样例**，不是历史本地 v0.1_A。

## 5. 第五周 I01–I10 的 v1.1 后续修复状态

实施范围仅 `TokenHubDB_v11_Issues_20261014`；细节和旧失败日志入口：[issue_fixes/README.md](v11/README.md)、[v1.1 数据字典](v11/data_dictionary_v11.md)、[正反例证据](../result/week6/issue_fixes/README.md)。

| 编号 | 当前实际状态 | 接手需要注意 |
|---|---|---|
| I01 | 已完成订单必须含明细、汇总一致，已支付明细禁止直接变更 | pending 草稿允许暂时无明细，写入入口需继续控制 |
| I02 | **用户已批准并实施**：同单同商品通过 quantity 合并，保留 UNIQUE | 新过程 `usp_W5_AddMergedOrderItem` 保留首次成交快照 |
| I03 | **用户已批准并实施**：必须先建立活跃 Users 记录才允许下单 | 不支持无用户记录的匿名订单；过程 `usp_W5_CreateRegisteredOrder` |
| I04 | **用户已批准并实施**：新上游账号自动创建且保留唯一库存 | 现有 8 个账号/8 条库存；其他直接配额更新仍要保证一致 |
| I05 | 新增调用记录会验证 provider、注册时间、账号创建/到期边界 | 修改已有 Users/Products/UpstreamAccount 等元数据的其它路径仍可影响旧数据 |
| I06 | `usp_W5_RecordUsage` 同事务维护余额、额度、库存、消费/库存日志、日周月汇总 | 订单支付充值等其他直接 DML 尚未收束 |
| I07 | **用户已批准并实施**：`created_source=manual/system`，人工必有 created_by，系统必须为空 | `assigned_to` 仍可空，旧 8 条任务为 manual |
| I08 | 新弱引用类型目标存在性及部分关联目标删除得到保护 | `InventoryLog.reference_type=manual` 的旧参考号含义未明确；不是通用 FK |
| I09 | 受控消费过程拒绝余额/额度不足，普通管理员直接改调用流水被阻止 | 旧逐事件负余额仍存在；余额/支付的其它直接写入入口未完全关闭 |
| I10 | 应用 Roles 与 SQL Server `hub_*` 权限角色分别建模，R01–R12 和权限反例已检查 | 不能将可自由填写 user_id 的管理过程直接授权给会员 |

v1.1 的 **13 个触发器、3 个过程** 仅在隔离副本安装，未纳入 [v0.1→v1.0 一键复现脚本](reproduction/run_from_snapshot.ps1)。如需端到端复现 v1.1，接手同事应先设计从**新 v1.0 迁移副本**分叉到新 v1.1 副本的幂等/目标名受限流程，再按 [issue_fixes 的 SQL 顺序](v11/README.md) 应用脚本，禁止在现有结果库上盲目重放。

v1.1 设计/代码：[approved_rules.sql](../sql/v11/approved_rules.sql)、[registered_order_workflow.sql](../sql/v11/registered_order_workflow.sql)、[record_usage.sql](../sql/v11/record_usage.sql)；可编辑模型：[ER v1.1](v11/er_diagram_v11.mmd)。

## 6. 未解决的问题：按优先级交接

1. **P0：旧数据来源核查（需要业务依据和独立授权）**。在旧 `TokenHubDB_v01_A` 及其 v1.0 迁移副本中，已发现订单早于注册 **20**、调用早于注册 **402**、上游有效区间或 provider 异常 **225**、按时间线余额负值事件 **1**。证据：[源库统计](../result/week6/regression/legacy_anomalies_source.log)、[副本统计](../result/week6/regression/legacy_anomalies_target.log)。不能通过编造付款/注册日期或 Token 数字使检查“变绿”；需要可信的历史原始事件/业务决策。仅作规范化迁移时，这些数量在源库和副本一致，说明未新引入。
2. **P1：收敛全部写入通道**。针对 I05/I06/I08/I09：为余额充值、订单支付、直接改 Users/Products/UpstreamAccount、库存额度、审计弱引用与异常处理等路径建立一致的事务边界和负例；确保经理/应用无绕过受控过程的权限。只有此项验证完整后才能说“业务约束全覆盖”。
3. **P1：v1.1 从零复现**。现成自动脚本止于规范化 v1.0；将 v1.1 隔离部署序列与权限/引用正反例纳入另一个新库回放，并明确是先前授权的业务规则，不要改变历史源代码 ZIP。
4. **P2：完成代码质量检查**。历史记录显示 Python `unittest` **22 项：12 PASS、10 skipped**（未配置独立集成测试数据库）；当时 sh 环境未配置仓库 `.venv` 和 `ruff`，所以 Ruff 未执行。接手者应在隔离环境安装/配置后重新核查 `ruff check/format`、完整 `unittest` 与必要的数据库集成测试；不能将 skipped 算作 PASS。
5. **P2：文档和小组审核**。第五周 [独立人工复核](../week5/independent_review.md) 有既有记录；**第六周新的 FD/无损分解/回归材料尚未记录由同事完成的独立签收**。接手同事应逐项核对候选码、FD 的业务前提、范式保留理由、回归与期末报告，再如实写入评审结论和 [AI 使用日志](../docs/ai使用文档.md)。[第六周计划](../plan/week6-normalization-migration-plan.md) 的较早阶段记录和部分文档中保留“当时未完成”的历史表述，以最新执行证据为准，不应静默改写历史。

**完成判定建议**：标准 v0.1→v1.0 迁移和重复复现已达可交付状态；“旧数据已修复 / 所有业务入口已无缺口 / 全量集成测试与独立签收完成”这三项**没有证据，不得标为 PASS**。

## 7. 交接者接手步骤与工作规范

1. 先执行 `git status --short`，记录本地 HEAD 和工作区变更；本轮开始前已有**另一项未提交的** `report/overview_modules.html/.mmd/.svg/.png`、`report/render_overview_modules.py` 及 README/ROADMAP/AI 日志相关改动。这些属于其他工作，不应擅自删改或顺带提交。
2. 按上节只读 QA 检查归档/代码/ER，定位 `result/week6/` 成功和失败两类日志，不要只查文件名为 PASS 就认定所有项目验收通过。
3. 与团队确认接下来处理的是**历史数据修复、写入流程封口、v1.1 复现、代码质量、报告审阅**中的哪一个，并为新数据库/脚本变更取得明确授权；不要默认拥有改动 `v01_A` 的权限。
4. 新增 SQL/ER/文档时随改随记 `docs/ai使用文档.md` 和 `docs/ai_usage_log.md`，更新 ROADMAP；不重写旧失败证据。ER 必须保留可编辑 Mermaid 源和渲染器，重新导出 SVG/PNG 并做 15 表/18 FK 与基数检查。
5. 修改 Python 需先建立项目 `.venv`，运行 Ruff 与 unittest，报告跳过的测试。运行 SQL 回归用 **新隔离库**；用户未授权时仅进行只读检查。
6. 本仓库此前提交为**本机本地 commit**，不等于已 push 到同事可访问的远程。交接文件若只在 sh 电脑可见，需要团队自行共享仓库或取得明确 push 许可。未经要求不自动 push、不删除历史库。

## 8. 交接核对清单

- [x] 确认完整的迁移前 Git 跟踪代码 ZIP 和 SHA-256
- [x] 新样例库从旧 ZIP 重建 → 隔离备份/还原 → v1.0 迁移 → R01–R12 → VFY01–VFY14，全链路实际两次通过
- [x] v1.0 / v1.1 数据字典、ER 可编辑源与 SQL 回归已保存
- [x] 已确认的 I02/I03/I04/I07 在 v1.1 副本实施并执行正反例
- [ ] 历史本地库的数据时间线/余额异常修复并验证
- [ ] 所有直接 DML/应用写入入口治理与完整权限回归
- [ ] v1.1 从历史 ZIP 开始的一键重放并独立验收
- [ ] 配置 Python 质量工具、减少集成测试 skipped 并重新归档结果
- [ ] 第六周方案与证据由接手同事**实际复核并记录**（当前尚无）
- [ ] 与同事完成仓库分发/交接确认（当前尚无）

**相关入口**：[第六周 README](README.md) · [任务 Plan](../plan/week6-normalization-migration-plan.md) · [结果证据](../result/week6/README.md) · [迁移前备份说明](../archive/week6-pre-migration/README.md) · [协作规范](../AGENT.md)。
