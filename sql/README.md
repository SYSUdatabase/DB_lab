# SQL 版本目录

SQL 按交付版本保存，**当前业务功能最新版为 [v1.1](v11/README.md)**。原版及规范化迁移保留，用于第六周规定的备份、迁移、回归与历史复现；不能把旧的 v0.1 建表文件当成最新结构。

| 目录 | 内容 | 说明 |
|---|---|---|
| [v01/](v01/README.md) | 原始 14 表、17 FK；建库/插入数据/CRUD/查询/视图/约束/权限/验收 | 第一阶段基线，供迁移前重建和对账 |
| [v10/](v10/README.md) | `migration.sql`、`regression.sql` | 将 v0.1 的统计周期拆成 `UsagePeriod` + `UsageSummaryCore`；迁移后 15 表、18 FK |
| [v11/](v11/README.md) | 业务保护、交易事务、退款表结构、Token 批次与退款回归 | **当前最终 SQL**：17 表、20 FK；增量应用于已迁移的 v1.0 副本 |

## 最新版本的执行入口

[第六周统一部署及 ER/数据字典](../week6/v11/README.md) 对应的 **一键重建**（在项目根目录运行）：

```powershell
python -B .\week6\v11\run_full.py --suffix NewV11Run01
```

该入口会创建新的隔离 v1.0、v1.1 数据库，先备份/还原、执行 `sql/v10/migration.sql`，再按顺序安装 `sql/v11/` 的修复 SQL、核对固定种子合成历史数据并执行支付、消费、补货与退款回归。**不覆盖 v0.1、现有 v1.0 或已经运行的 v1.1。** 不要直接对正式库从中间开始运行增量 SQL。

v0.1 独立建库入口仍是 `tools/run_v01.ps1`，使用 `sql/v01/`；历史代码快照另在 [archive](../archive/week6-pre-migration/README.md)。第二阶段报告保持不变。
