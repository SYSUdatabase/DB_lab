# 第六周：函数依赖、规范化与迁移执行结果

**同事接手请先读：[第六周工作交接上下文](HANDOFF_CONTEXT.md)**。该文档按当前 Git 提交、数据库和运行证据列出交付、遗留项及安全操作步骤；旧章节保留各阶段形成时的历史状态。

## 结论

第六周批准的 **UsageSummary → UsageSummaryCore + UsagePeriod** 拆分已在隔离副本 `TokenHubDB_v10_W6_20261014` 成功实施。实际结果 **15 张物理表、18 条可信 FK、11 个视图**（包括旧 `dbo.UsageSummary` 查询兼容视图）。原 `TokenHubDB_v01_A` 数据库未改动。**第六周迁移与结构/权限回归成功，但源库遗留 VFY12/13 数据异常尚未修复，不能宣称旧业务数据完整性全量通过。**

## 交付目录

| 作业要求 | 实际文件与状态 |
|---|---|
| 14 表的函数依赖、候选码、1NF/2NF/3NF、三种更新异常 | [dependency_normalization.md](dependency_normalization.md)：完成 |
| 保留/拆分、无损连接与依赖保持 | [redesign_decisions.md](redesign_decisions.md)：已按用户批准方案实施 |
| 迁移与数据映射 | [sql/migration.sql](../sql/migration.sql)：仅针对已验证的隔离副本，成功日志见下文 |
| 迁移后回归、合法/非法写入、四类权限 | [sql/regression.sql](../sql/regression.sql)：R01–R12 全部 PASS |
| 目标数据字典和 ER 可编辑源及导出 | [data_dictionary_v10.md](data_dictionary_v10.md)、[er_diagram_v10.mmd](er_diagram_v10.mmd)、[er_diagram_v10.svg](er_diagram_v10.svg)、[er_diagram_v10.png](er_diagram_v10.png) |
| 验证、报告及 AI 记录 | [report_material.md](report_material.md)、[结果目录](../result/week6/README.md)、[AI 使用记录](../docs/ai使用文档.md) |

项目提供 [render_er_v10.py](render_er_v10.py) 以可编辑的 Mermaid ER 源重新生成矢量图，使用 [qa_week6.py](qa_week6.py) 对照 SQL Server 的 18 条外码和图像输出；兼容视图不计入 ER 的 15 张物理表。

## 实际执行的数据库变更

迁移前：`dbo.UsageSummary` 为物理表，有 3394 行，每行重复保存 `period_end`。

迁移后：
- `dbo.UsagePeriod(period_type,period_start,period_end)`：99 条不重复的日/周/月周期定义，复合主码和日期 CHECK 强制统一周期规则。
- `dbo.UsageSummaryCore`：3394 条，旧的 summary_id、业务键、指标与旧 Users/Products FK 均保留；新增 `(period_type,period_start)` FK 指向 UsagePeriod，不再保存 `period_end`。
- `dbo.UsageSummary`：同名兼容**只读视图**，JOIN 两张表恢复旧 10 列，只兼容原查询，**不兼容旧的 INSERT/IDENTITY_INSERT**。新写入需先存在周期定义，再写 UsageSummaryCore。
- 源库先前只有 9 个视图且 `v_InventoryStatus` 缺少现有官方脚本中定义的列；在目标副本按 `sql/view.sql` 补齐 `v_CustomerService` 和 `v_InventoryStatus`。正式源库仍维持 9 个视图。

## 回归执行及边界

| 检查 | 结果 |
|---|---|
| 数据迁移与隔离 | 备份/VERIFYONLY/还原成功；目标库结构迁移成功 |
| 迁移后 15 表、18 个可信 FK、11 视图 | PASS |
| 99 个周期与 3394 条汇总；按业务键无损还原 | PASS |
| 迁移前后业务基准（剔除新增权限行）共 3763 行 | **0 差异** |
| 订单、商品销售、库存、余额和调用结果双向 EXCEPT | PASS |
| 合法增写+回滚；重复键 / 日期 CHECK / 复合 FK 反例 | PASS（预期错误号正确） |
| 管理员 / 店员 / 会员 / 游客及独立 VFY14 权限检查 | PASS |
| v0.1 源库基线内容 SHA-256 前后保持一致 | PASS |
| 旧 VFY01–VFY11 | PASS（结构计数按 v1.0 适配） |
| **旧 VFY12/VFY13** | **未通过：源库继承的时间线与历史余额异常** |

具体 inherited 问题数（源库 = 目标库）：订单早于注册 **20**；调用早于注册 **402**；provider/上游时间区间不合规 **225**；历史负余额事件 **1**。这四项原有数据缺陷不属于本次周期范式拆分，没有修改交易数据以掩盖错误。两份只读计数见 [源库](../result/week6/regression/legacy_anomalies_source.log) 与 [副本](../result/week6/regression/legacy_anomalies_target.log)。

## 执行命令与重跑限制

```powershell
# 在 D:\Desktop\DB\DB_lab 目录
# 只适用于已还原但尚未迁移的 TokenHubDB_v10_W6_20261014 副本
sqlcmd -S 'localhost\SQLEXPRESS' -d 'TokenHubDB_v10_W6_20261014' -E -C -b -i .\sql\migration.sql

# 已迁移的数据库：运行回归，不要重复运行 migration.sql
sqlcmd -S 'localhost\SQLEXPRESS' -d 'TokenHubDB_v10_W6_20261014' -E -C -b -i .\sql\regression.sql
python -B .\week6\qa_week6.py
```

**恢复限制**：`week6/prepare_copy.sql`、`sql/migration.sql` 都有硬编码目标名和拒绝已存在对象的防覆盖检查。已迁移副本上不得重复执行；需要复现时必须审核备份/恢复目标并选择**新的数据库/物理文件名**，更新脚本白名单后另行授权。备份保存在 SQL Server Backup 目录，未提交到 Git。旧的 `sql/02_insert_data.sql` 只适配原 v0.1，不可直接向 v1.0 的兼容视图写入。

## 执行过程和失败记录

1. 第一次迁移在数量检查时报 51610，安全回滚：源库实际少 `v_CustomerService`；修正后的 [run_v2.log](../result/week6/migration/run_v2.log) 成功，原失败 [run.log](../result/week6/migration/run.log) 保留。
2. 完整校验第一次因源库原视图缺少 `quota_headroom` 失败。使用 [align_legacy_views.sql](align_legacy_views.sql) 仅修复目标，官方定义已整合到最新 `migration.sql` 以便未来从初始备份重新执行。
3. 完整校验第二次走到 VFY12 因现存 20 条订单时间顺序错误终止；另以 `legacy_anomalies.sql` 保留所有四类继承问题对照。
4. 所有本次结构回归 R01–R12 在修复视图后再次通过，VFY14 独立复核通过；源库前后 SHA-256 一致。

本次实施过程中未删除或覆盖原 v0.1 表、数据库、旧 Git 证据文件；新数据副本仅供第六周实验，**暂未对本次迁移后的修改执行新的 Git commit/push**。

## 最终项目检查补充

`python -B week6/qa_week6.py`：15 实体/18 FK 对照数据库实际列，SVG/PNG 解析，56 条文档相对链接均通过。旧 `week5/qa_week5.py` 也继续通过。Python AST 静态语法检查 2 个第六周脚本通过。

`python -B -m unittest discover -s tests -v`：共 22 项，12 项通过、10 项因未设置专门集成测试数据库而 **skipped**（非通过）。项目电脑当前没有 `.venv` 和 `ruff` 命令，未执行 Ruff check/format；此项不应冒称完成。真正的 v1.0 SQL 结构/权限回归由 R01–R12 与 VFY14 提供。无额外提交或推送。

## v1.1：第五周业务选择已落地（2026-10-14）

已在独立 v1.1 副本实施 I02/I03/I04/I07 的最终业务口径，结果见 [v1.1 约束和数据字典](v11/data_dictionary_v11.md)、[可编辑 ER](v11/er_diagram_v11.mmd)、[功能与回归证据](v11/README.md)。原 v1.0 迁移结果和基准未改，I05/I06/I08/I09 的其他写入路径和继承的历史异常仍需后续处理。

## 第六周完整历史代码备份与可重复迁移（2026-10-14）

第六周开始前的完整 Git 跟踪项目已归档在 [迁移前代码 ZIP](../archive/week6-pre-migration/DB_lab_pre_week6_c8d4e64_full_source.zip)（`c8d4e64`，344 个文件，SHA-256 见 [备份说明](../archive/week6-pre-migration/README.md)）。新增 [一键复现入口](reproduction/README.md)、[独立重建脚本](reproduction/run_from_snapshot.ps1) 与 [两次复现实测日志](../result/week6/reproduction/README.md)。

**完整从代码复现已通过**：从 ZIP 解压旧版、用历史 `tools/run_v01.ps1` 建一套全新的 v0.1（14 表/17 FK/10 视图）、备份/还原到另一个空库、执行 `sql/migration.sql` 得到 v1.0（15 表/18 FK/11 视图），R01–R12 与 VFY01–VFY14 **全部 PASS**，迁移前后 3763 条非权限业务记录差异 0。自动脚本已用独立 `W6Auto261014` 后缀再次实跑，不依赖原 v0.1_A 数据库。

**两种来源不可混同**：历史本地 v0.1_A 缺少正式视图并有旧数据异常；从迁移前代码重建的标准 v0.1 使用 10 个视图并通过旧数据验证。为兼容这两种已确认基线，`sql/migration.sql` 已增加 9/10 视图的前置核验与条件补建客服视图，其他未识别结构仍停止。


## v1.1 后续加固与历史样例核对（2026-10-17）

新增 [加固与部署说明](v11/README.md)、[历史数据修复脚本](v11/repair_generated_history.py)、[加固 SQL](v11/03_close_write_paths.sql) 及 [自动核验入口](v11/validate_hardened.py)。在 **xiao_ruan 的新隔离数据库** TokenHubDB_v11_Harden261017B 实际完成备份、v0.1→v1.0→v1.1、合成历史核对修复和写入加固；修复前 20/402/225/1，修复后 **0/0/0/0**。新增受控支付/补货，3000 条可追溯使用流水，11 个新保护触发器；原有 13 个触发器保留。适配后的 VFY01–VFY14、X01–X10、Y01–Y04 和原 v1.1 五组测试均已通过。

这属于**新的本机已核验副本**，没有覆盖队友 sh 上的原 TokenHubDB_v11_Issues_20261014，也未改变 v0.1/v1.0；原 sh 数据库的备份文件尚须在 sh 环境复查。合成时间校正只适用于严格指纹匹配的固定种子样例。退款等尚缺业务规则的操作需在后续应用事务中设计，不将禁止无控制直写误称为完整退款功能。


## 2026-10-17 最新完整 v1.1（含退款）

**以 [统一 v1.1 目录](v11/README.md) 为当前入口**，不再分别使用早期的 issue_fixes/hardening 目录。结构升级为 **17 表、20 FK**（新建 Token 批次与退款责任账本），支持已消费部分不退、按未消费 Token 比例计算退款、重复退款不重复扣减、外部支付成功凭证单独核对。所有脚本、[ER](v11/er_diagram_v11.mmd)、[数据字典](v11/data_dictionary_v11.md)、验证入口和结果统一可查。

`TokenHubDB_v11_Full261017D` 在 xiao_ruan 本机从 v0.1 完整重建并通过 R01–R12、VFY01–VFY14、X01–X10、Y01–Y04 与 RF01–RF06。历史数据四类异常修复前 20/402/225/1，副本修复后 0/0/0/0。原 v0.1 和队友 sh 既有 v1.1 均未改动；外部支付功能仍须接入支付系统后才能真正向用户退钱。第二阶段报告留待本阶段结束。
