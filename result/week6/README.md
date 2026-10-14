# 第六周证据索引（P0/P1）

- 源库 `TokenHubDB_v01_A`；隔离副本 `TokenHubDB_v10_W6_20261014`。
- `baseline/prepare_copy.log`：SQL Server BACKUP COPY_ONLY/CHECKSUM、RESTORE VERIFYONLY、RESTORE DATABASE WITH MOVE 通过。
- `baseline/source_semantics.failed_collation.txt`：第一次基准查询的 collation 451 错误，单独保留；`baseline/source_semantics.txt` 为修复后基准。
- `baseline/source_semantics_v2.txt`、`baseline/copy_before_v2.txt`：源库与副本迁移前业务记录各 3837 行，SHA-256 均为 `A73CB20D7DAA334328AABC25EB06CDD4FE6977F20C2EF86302406176AACB8EEC`。
- `baseline/fd_checks.log`：14 表、17 FK，明细计算/订单汇总/库存差异均为 0；周期终点无相同键的冲突样例，不能据此保证业务 FD。
- `migration/`、`regression/`：**尚未实施，暂无测试结论**；待 P2 目标结构获用户确认后进入 P3/P4。
- 数据库 `.bak` 位于 SQL Server 安全备份目录，未纳入仓库，禁止提交；正式 v0.1 原库未修改。
