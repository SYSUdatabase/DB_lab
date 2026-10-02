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
