# v1.0 规范化迁移 SQL

从已备份并还原的 v0.1 副本出发：

- [migration.sql](migration.sql)：分离 `UsageSummaryCore` / `UsagePeriod`，建立只读兼容视图，验证约束和基线；脚本有初始状态和库名检查，拒绝直接修改 v0.1。
- [regression.sql](regression.sql)：R01–R12，覆盖数据无损连接、订单/销售/库存/余额/使用记录与原基线一致、非法写入及权限。

范式和决策依据参见 [第六周设计](../../week6/dependency_normalization.md) 与 [重构方案](../../week6/redesign_decisions.md)。若需完整复现 v1.1（含退款），请使用 [最新部署入口](../../week6/v11/README.md)，不要单独把此迁移当成最新版业务功能。
