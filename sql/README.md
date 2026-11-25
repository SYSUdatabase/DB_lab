# SQL 版本目录

SQL 按交付版本保存，**当前业务功能最新版为 [v1.1](v11/README.md)**。原版及规范化迁移保留，用于第六周规定的备份、迁移、回归与历史复现；不能把旧的 v0.1 建表文件当成最新结构。

| 目录 | 内容 | 说明 |
|---|---|---|
| [v01/](v01/README.md) | 原始 14 表、17 FK；建库/插入数据/CRUD/查询/视图/约束/权限/验收 | 第一阶段基线，供迁移前重建和对账 |
| [v10/](v10/README.md) | `migration.sql`、`regression.sql` | 将 v0.1 的统计周期拆成 `UsagePeriod` + `UsageSummaryCore`；迁移后 15 表、18 FK |
| [v11/](v11/README.md) | 业务保护、交易事务、退款表结构、Token 批次与退款回归 | **当前最终 SQL**：17 表、20 FK；增量应用于已迁移的 v1.0 副本 |

## 最新版本的执行入口

[第六周统一部署及 ER/数据字典](../archive/coursework/week6/v11/README.md) 对应的 **一键重建**（在项目根目录运行）：

```powershell
python -B .\db_tools\v11\run_full.py --suffix NewV11Run01
```

该入口会创建新的隔离 v1.0、v1.1 数据库，先备份/还原、执行 `sql/v10/migration.sql`，再按顺序安装 `sql/v11/` 的修复 SQL、核对固定种子合成历史数据并执行支付、消费、补货与退款回归。**不覆盖 v0.1、现有 v1.0 或已经运行的 v1.1。** 不要直接对正式库从中间开始运行增量 SQL。

v0.1 独立建库入口仍是 `tools/run_v01.ps1`，使用 `sql/v01/`；历史代码快照另在 [archive](../archive/week6-pre-migration/README.md)。第二阶段报告保持不变。


## 第10周可选增量

完整v1.1 Web基线后可安装[week10](week10/README.md)，使用app_prepare.py --with-week10一次构建。新增销售/补货/折扣函数、库存调整与受控Web入口，安装后19表26FK。第二阶段默认构建入口保持18表。

## 第11—12周增量

第10周之后依次安装[week11](week11/README.md)（库存审计与订单完成规则触发器、窗口查询）和[week12](week12/README.md)（分类层级递归查询、订单完成与补货入库事务），使用app_prepare.py --with-week10 --with-week11 --with-week12一次构建。原支付与补货完成过程保留名称，改为调用第12周事务。

## 第13周并发控制

[双会话脚本与操作顺序](week13/README.md)覆盖锁等待、隔离对照、死锁、同序更新和实际订单竞争。固定的供应商锁顺序随第12周事务安装；独立实验表只在专用批次检查时创建。
