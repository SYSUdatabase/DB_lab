# 第六周阶段报告素材（截至 P2 方案）

## 已完成的设计与分析

按 `week5` 物理 ER 模型和当前 14 表 DDL 逐一整理 `dependency_normalization.md` 的候选码、FD、1NF/2NF/3NF 与三类异常。明细计算后存储的小计存在非码→非码 FD，两个 CHECK 约束保证同表公式但并没有取消冗余；历史单价和 Token 档位属于必要成交快照，不能从当前套餐现价回算。

`UsageSummary` 的 `(period_type,period_start)→period_end` 仅在全局统一周期规则成立时可以视为业务 FD；现有样例未见同键不同终点，不能替代业务批准。条件性候选分解 `UsagePeriod` 与 `UsageSummary` 的无损/依赖保持分析见 `redesign_decisions.md`。其余关系保留当前已确认键/外码与历史流水语义。

## P0 已取得的依据

`TokenHubDB_v01_A` 已成功备份并校验、还原为新隔离副本 `TokenHubDB_v10_W6_20261014`。源库与副本按订单明细、销售、库存、余额、使用汇总与角色权限生成的基准文本各 3837 行，SHA-256 一致。修复了元数据角色查询的 collation 冲突，保留初次报错记录。证据见 `../result/week6/README.md`。

## 尚未产生的执行结论

具体迁移范围尚未获用户确认；`migration.sql`、`regression.sql`、目标 ER 图及迁移后对账结果**均不能记为完成**。批准后按第六周计划，在副本执行 DDL/数据映射以及订单、销售、库存、正反例和权限回归，保留所有差异和错误日志。
