# 第六周规范化与数据库迁移结果

## 结构选择与 FD

14 表逐项的 1NF/2NF/3NF、候选码、主要 FD 及插入/修改/删除异常见 [规范化分析](dependency_normalization.md)。重点是现有代码将统计周期定义为 daily=当天、weekly=周一至周日、monthly=自然月首至月末，成立 `(period_type,period_start)→period_end`。这一非码前件只依赖 UsageSummary 复合候选码的一部分，属于 2NF 违例的依据；`OrderDetails` 的金额/Token 小计也有非码→非码公式 FD，但保留 CHECK 保护的受控计算存储及历史单价快照，避免破坏旧的插入入口。

分解 `UsageSummary` 为 `UsagePeriod(period_type,period_start,period_end)` 和 `UsageSummaryCore(summary_id,user_id,product_id,period_type,period_start,metrics...)`。交集 `(period_type,period_start)` 为 UsagePeriod 的主码，配合汇总核心的可信复合 FK，重建无损；每一个关键 FD 在一张子表中可保留。新视图 `dbo.UsageSummary` 继续提供旧 10 列查询语义。ER 源文件 `er_diagram_v10.mmd` 包含 15 张表与 18 条实际 FK，脚本 `render_er_v10.py` 导出 SVG/PNG。

## P0 基线及隔离

使用 `week6/prepare_copy.sql` 从现存 v0.1 库 `TokenHubDB_v01_A` 完成 COPY_ONLY、CHECKSUM 备份、VERIFYONLY 和隔离恢复，生成 `TokenHubDB_v10_W6_20261014`。旧表与历史证据均不覆盖。源/副本迁移前 3837 行业务/权限基准 SHA-256 相等：`A73CB20D7DAA334328AABC25EB06CDD4FE6977F20C2EF86302406176AACB8EEC`。

## P3 数据迁移与发现的旧版本差异

- 第一次 `sql/v10/migration.sql` 在结构计数检查时主动失败并回滚。核查确定源 v0.1_A 仅有 9 个视图，缺少正式 `sql/v01/view.sql` 定义的 `v_CustomerService`。修正后第二次在副本成功：15 张表、18 条可信外码、11 视图；3,394 条汇总保留；99 种固定周期提取为独立表。
- 旧库的 `v_InventoryStatus` 与正式脚本不一致（没有 `quota_headroom` 等列）。在目标副本执行 `week6/align_legacy_views.sql` 后，该视图与正式 `sql/v01/view.sql` 一致；这一修复也整合进最新版 `sql/v10/migration.sql`，供未来从未迁移副本重跑。
- 迁移事务在 `sql/v10/migration.sql` 中包含库名、原始表/FK/行数、固定周期规则、冲突数量前置检查和 TRY/CATCH 回滚。脚本会拒绝重复迁移，原 v0.1 库不在其允许目标内。无任何数据被当作“新版本样例”重新生成覆盖。
- 新写入路径须使用 `UsagePeriod` 与 `UsageSummaryCore`；旧的 dbo.UsageSummary 现在是查询兼容视图。历史生成器与 v0.1 `02_insert_data.sql` 保留给原版使用，不应假装已兼容新视图。

## P4 实际核验和结果

| 核验类型 | 结果 / 证据 |
|---|---|
| R01–R12，包括表/FK/视图、无损联接、订单/销售/库存/余额双向 EXCEPT、正反例、权限 | 全部通过：`../result/week6/regression/regression_run_02.log` |
| 源/副本迁移前 3837 行基线 | 一致：`../result/week6/baseline/` |
| 迁移前后非权限业务记录 3763 行 | 差异 0：`../result/week6/regression/copy_after.txt` 与旧基准比对 |
| 迁移后直接 SQL 集合比较 | UsageSummary、OrderDetails、Orders、v_ProductSales、Inventory、TokenBalances、TokenUsageLogs 双向 EXCEPT 均空 |
| 新周期复合候选码、合法写入并回滚、CHECK 和 FK 反例 | 合法成功，反例报 2601/2627 或 547，且数据恢复 |
| 4 类角色 | manager 在 15 表 CRUD；staff 有客服视图读但无新表权；会员/游客无新对象访问，拒绝报 229；独立 `VFY14` 也通过 |
| 源库变化检查 | 迁移前后源业务基准 SHA-256 完全一致 |
| v1.0 ER 15 实体/18 FK、图片、相对链接 | `qa_week6.py` 通过 |
| **原 v0.1 VFY12/VFY13** | **未通过（迁移前即存在的历史数据问题）** |

以 `legacy_anomalies.sql` 在源库和副本单独核对：订单创建先于注册 20 条；使用先于注册 402 条；上游有效时间/provider 违例 225 条；事件时间线余额小于零的历史事件 1 条。四项前后计数完全相同。正式适配的 `week6/verify_v10.sql` 通过 VFY01—VFY11，在 VFY12 因旧数据报 51360；独立执行 `verify_v10_roles.sql` 的 VFY14 通过。**不得宣称 VFY12/13 通过或全部历史业务不变量合格**。

## 剩余影响与处理边界

1. v0.1_A 本身的数据与部分视图版本早于仓库官方脚本，需要在后续单独选择数据修复/重新复现策略；本次迁移不能“顺便修改”旧订单和用量历史而掩盖基线不一致。
2. 原 `dbo.UsageSummary` 的 INSERT/UPDATE 直接写入方式不兼容 v1.0 只读视图。后续真正接入应用的代码必须使用 `UsageSummaryCore` 和 `UsagePeriod` 的事务写入路径。
3. 本次已获用户批准的是**副本上的规范化拆分和同步验证**，不包括清理老库、覆盖源库或删除历史证据；也未包含对第五周未决散客、补货创建人等规则的擅自修改。
4. 若需重新迁移，应从安全备份恢复到**新的、未占用的库名/物理文件名**，审查修改硬编码库名的保护条件后再运行，不得在已经迁移的库上重放 P3。
