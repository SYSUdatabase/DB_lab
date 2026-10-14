# 第六周：规范化与迁移（进行中）

**当前阶段：P0、P1 已完成；P2 已形成待批准方案。P3 迁移、P4 回归尚未实施。** 原 `TokenHubDB_v01_A` 保持不变。不要将当前材料称为已完成第六周全部任务。

## 已有文件

| 文件 | 当前用途 |
|---|---|
| [dependency_normalization.md](dependency_normalization.md) | 14 表候选码、FD、1NF/2NF/3NF、插入/修改/删除异常和假设性无损分解 |
| [redesign_decisions.md](redesign_decisions.md) | 各表保留/拆分决策、周期维表候选方案、无损连接与依赖保持证明；**仍待用户确认** |
| [prepare_copy.sql](prepare_copy.sql) | 仅用于 2026-10-14 创建副本的备份/还原脚本，不能在既有库上重新运行 |
| [baseline.sql](baseline.sql) | 只读源/副本业务基准查询（订单、明细、销售、库存、汇总、角色与权限） |
| [fd_checks.sql](fd_checks.sql) | 只读数据与依赖异常统计 |
| [第六周计划](../plan/week6-normalization-migration-plan.md) | 阶段检查点与最终验收要求 |

## 只读与隔离副本证据

- 源数据库：`TokenHubDB_v01_A`，从备份还原的新副本：`TokenHubDB_v10_W6_20261014`。
- 备份和还原成功输出：[prepare_copy.log](../result/week6/baseline/prepare_copy.log)；数据库备份文件保存在 SQL Server Backup 目录，不属于 Git 仓库。
- 初次排序规则错误已单独保留于 [source_semantics.failed_collation.txt](../result/week6/baseline/source_semantics.failed_collation.txt)，修复后的 [source_semantics.txt](../result/week6/baseline/source_semantics.txt) 为有效基准。
- 修正后 [源库结果](../result/week6/baseline/source_semantics_v2.txt) 与 [副本迁移前结果](../result/week6/baseline/copy_before_v2.txt) 各 3837 行，SHA-256 完全相同。
- [FD 检查 SQL](fd_checks.sql) / [FD 检查输出](../result/week6/baseline/fd_checks.log)：明细金额/Token 公式、订单金额、库存额度、同单同商品重复均为零异常。样例统计并不证明业务 FD。
- 备份中可能含业务敏感信息，严禁提交 Git；不得读取或展示 api_key、password_hash 等列的值。

## 尚待决策

`UsageSummary` 若全局共享固定周期 `(period_type,period_start)→period_end`，可无损分解为 `UsagePeriod` 和去除 `period_end` 的 `UsageSummary`；若周期可定制，则 FD 不成立，不应拆。迁移决定、使用方 SQL 改动与回滚策略见 [P2 方案](redesign_decisions.md)。

当前尚无 `migration.sql` 实际执行结果、`regression.sql` 结果及新目标 ER 图，因为目标关系模式还未获得批准。批准后按计划仅在隔离副本迁移，验证订单明细、销售统计、库存、合法/非法写入与四类数据库角色权限。

本目录内容为当前已实施步骤，不作为 P3/P4 PASS 的替代品。
