# 正式 SQL 入口

所有脚本使用 SQLCMD 变量 `$(DatabaseName)`。默认由 [复现工具](../tools/run_v01.ps1) 传入；在 SSMS 中需要 SQLCMD 模式及相应变量。

执行顺序：00 → 01 → 02 → 03 → view → query → constraint → role → verify → signature。Q09 使用库存视图，因此必须先运行 view。

| 文件 | 内容 |
|---|---|
| 00_create_database.sql | 新库、恢复模式；已有库拒绝覆盖 |
| 01_create_tables.sql | 14 表与主码、候选码、外码和基础约束 |
| 02_insert_data.sql | 当前生成器的固定样例；40 用户、100 订单、184 明细、3000 调用 |
| 03_crud_demo.sql | 商品、库存、订单 CRUD，演示后回滚 |
| query.sql | Q01～Q12，连接、聚合、HAVING、子查询及边界查询 |
| view.sql | 4 个经营统计视图和 6 个权限用途视图 |
| constraint.sql | 3 个跨列 CHECK；C01～C14 正反例 |
| role.sql | 四角色、五演示用户；R01～R17 允许与拒绝 |
| verify.sql | VFY01～VFY14，总量、逐行、时间线和有效权限 |
| signature.sql | 按主键排序的 14 表业务内容 SHA-256 |

当前生成入口为 [tools/datagen.py](../tools/datagen.py)，不再从历史第三周样例覆盖正式 SQL。更新样例必须运行生成器自检、回归和 SQL Server 复现，明确同步固定期望值；禁止通过放宽断言迁就错误数据。

调用不能早于注册；按 paid_at 充值并逐事件验证余额。同秒先充值后消费。上游 provider 必须匹配，调用时间小于 expires_at；expires_at 为 NULL 表示没有到期限制。当前账号状态为快照信息，缺少状态变更历史时不推断其过去一直 suspended/depleted。

库存快照固定为 2026-09-22T23:59:59。Q06 的可用账号筛选与 stock_state 的纯额度判定不同。跨表不变量当前由独立验收检查，真实写事务的即时维护留给后续阶段。

课程要求映射见 [任务书索引](../docs/requirements/README.md)，历史周次材料见 [archive](../archive/README.md)。

## 第六周 v1.0 副本迁移

- [migration.sql](migration.sql)：仅允许在已备份并还原、且尚未迁移的 `TokenHubDB_v10_W6_20261014` 上执行。统一统计周期迁入 `dbo.UsagePeriod`，原汇总表成为 `dbo.UsageSummaryCore`，兼容只读视图 `dbo.UsageSummary` 恢复旧列。事务失败回滚，禁止将脚本指向原 `TokenHubDB_v01_A` 或重复运行。
- [regression.sql](regression.sql)：仅对迁移后的隔离副本运行，校验 15 张表/18 FK/11 视图、汇总无损连接、旧订单/销售/库存/余额/调用双向等价、合法与非法写入、四类角色权限以及原库未变。
- 完整分析及现有数据限制见 [week6 README](../week6/README.md) 和 [结果记录](../result/week6/README.md)。旧 `02_insert_data.sql` / `run_v01.ps1` 保留为 v0.1 的原始复现入口，不能直接作为 v1.0 的写入/重建脚本使用。

## 迁移兼容性与从旧代码复现

`sql/migration.sql` 增加对**两种已核实 v0.1 基线**的前置判定：历史本地 9 个视图（缺 `v_CustomerService`）或从第六周前源码重建的 10 个视图。对 9 视图路径按官方定义补建，10 视图路径保留原客服视图；两条路径最终要求 v1.0 11 视图，不接受未识别的视图组合。这不放宽 14 表、17 FK、3394 汇总和 99 周期及约束可信性的强制检查。

[完整历史源代码备份](../archive/week6-pre-migration/README.md)、[从代码独立重建 + 规范化迁移](../week6/reproduction/README.md)。复现脚本只在全新的隔离数据库上运行，通过名称模板复制派生 SQL，不直接修改本文件；已自动完成并通过全部 R01–R12 与 VFY01–VFY14。
