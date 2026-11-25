# 第六周：从完整历史源代码重建并迁移的证据

代码源为 `archive/week6-pre-migration/DB_lab_pre_week6_c8d4e64_full_source.zip`，原 Git 提交 `c8d4e64`，344 个文件、SHA-256 `D2DFA2F23504050ACBA3F4BDE95A7946DCA72D29F6599A6D75A67C16DDE5743C`。运行说明见 [week6/reproduction/README.md](../../../week6/reproduction/README.md)。此目录只记录复现证据，不保存原 SQL Server MDF/LDF/BAK，也不包含凭据。

## 一、分步核验：W6Replay261014

- 原历史 ZIP 解压在仓库旁 `D:\Desktop\DB\DB_lab_replay_c8d4e64`；从其中旧 `tools/run_v01.ps1` 建新库 `TokenHubDB_v01_W6Replay261014`，旧建库、数据、查询、约束、角色、`verify.sql`、`signature.sql` 全部 PASS。
- [copy_replay_261014.sql](../../../week6/reproduction/copy_replay_261014.sql)、[copy_replay_261014.log](copy_replay_261014.log)：SOURCE COPY_ONLY + CHECKSUM、RESTORE VERIFYONLY、还原到独立 `TokenHubDB_v10_W6Replay261014`。迁移前源/副本 3837 行输出 SHA-256 相等：`A12B5ED2FFD832C2DC5DDC7988446212E8D18695260A90382B94F060286C5FF5`。
- [migration_replay_261014.sql](migration_replay_261014.sql)、[migration_replay_261014.log](migration_replay_261014.log)：从主仓库当前 `sql/v10/migration.sql` 派生，只替换允许的目标数据库名；迁移得到 15 表、18 FK、11 视图、99 个周期定义、3394 条汇总，PASS。
- [regression_replay_261014.sql](regression_replay_261014.sql)、[regression_replay_261014.log](regression_replay_261014.log)：原始回归模板适配重建的源/目标库名及标准 v0.1 的 10 个源视图后，R01–R12 全部 PASS。
- [verify_v10_replay_261014.sql](verify_v10_replay_261014.sql)、[verify_v10_replay_261014.log](verify_v10_replay_261014.log)：VFY01–VFY14 全部 PASS，包含历史注册/调用时间线和逐事件余额。

## 二、完整自动脚本再次核验：W6Auto261014

在同一台 sh 电脑新建另一对数据库：`TokenHubDB_v01_W6Auto261014`、`TokenHubDB_v10_W6Auto261014`。用 [run_from_snapshot.ps1](../../../week6/reproduction/run_from_snapshot.ps1) 从 ZIP 开始再次完整执行。

- [replay_manifest.txt](W6Auto261014/replay_manifest.txt)：旧 Git 源版本、ZIP 哈希、创建的库名、业务基准哈希和测试结论。
- [historical_bootstrap.log](W6Auto261014/historical_bootstrap.log)：旧版代码建库、样例、验证、签名 PASS。
- [copy_replay.log](W6Auto261014/copy_replay.log)：安全备份/还原 PASS。
- [migration_replay.log](W6Auto261014/migration_replay.log)：规范化迁移 PASS。
- [regression_replay.log](W6Auto261014/regression_replay.log)：R01–R12 全部 PASS。
- [verify_replay.log](W6Auto261014/verify_replay.log)：VFY01–VFY14 全部 PASS。
- [copy_before.txt](W6Auto261014/copy_before.txt)、[copy_after.txt](W6Auto261014/copy_after.txt)：剔除目标结构变化而新增的权限行后，两份均为 3763 条非权限业务基准，差异 **0**。

完整自动脚本运行耗时约 19 秒（仅本台电脑的这次记录，不代表其它环境耗时）。脚本不会删除/覆盖旧库；重跑要使用新的后缀。

## 三、与既有数据库结果的区别

原项目 `TokenHubDB_v01_A` 在历史本地快照中只有 9 个视图，并有订单早于注册、调用有效性、历史负余额问题；这些旧数据仍保留在之前的 [legacy_anomalies 日志](../regression/legacy_anomalies_source.log) 中，没有被本次修改。

历史源代码 `c8d4e64` **重新生成的**标准 v0.1 数据库含 10 个视图，原旧版全量验证已通过。当前 `sql/v10/migration.sql` 在明确校验基线的前提下支持 9 / 10 两种已确认视图版本，此次自动流程使用 10 视图路径。只有对完整代码快照重新建库的结果才可登记为“全量 VFY01–VFY14 PASS”；不能据此把旧 `TokenHubDB_v01_A` 的历史错误标成已修复。
