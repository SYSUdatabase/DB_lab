# 第六周执行证据

**原库**：`TokenHubDB_v01_A`（未写入）。**目标副本**：`TokenHubDB_v10_W6_20261014`（已按批准方案迁移）。SQL Server 完整备份在服务端 Backup 目录，不纳入 Git。

## P0 保护和基准

- `baseline/prepare_copy.log`：备份、VERIFYONLY、独立还原成功。
- `baseline/source_semantics.failed_collation.txt`：首次 SQL collation 451 错误，保留失败信息。
- `baseline/source_semantics_v2.txt`、`baseline/copy_before_v2.txt`：迁移前各 3837 行，SHA-256 都为 `A73CB20D7DAA334328AABC25EB06CDD4FE6977F20C2EF86302406176AACB8EEC`。
- `baseline/fd_checks.log`：明细公式、订单汇总与库存关系差异为 0；3394 条汇总具有 99 种周期。

## P3 迁移

- `migration/run.log`：第一次结构计数检查报 51610 并回滚，根因为 v0.1_A 的视图数与官方 `view.sql` 不一致。
- `migration/run_v2.log`：迁移成功。15 张表、18 FK、11 视图、99 个周期、3394 条汇总。
- `migration/align_legacy_views.log`：补齐目标副本的 v_InventoryStatus 缺失列，源数据库未改。

## P4 回归

- `regression/regression_run_01.log` 与 `regression/regression_run_02.log`：R01–R12 完整成功，含双向 EXCEPT、可信 FK/CHECK、合法写入/回滚、负例与四角色权限。
- `regression/copy_after.txt`：迁移后订单/明细/销售/库存/余额/用量、角色权限基准。与迁移前比较，剔除有意新增的权限行后 **3763 条非权限记录差异为 0**。
- `regression/source_after.txt`：迁移后重新读取旧库基准，SHA-256 与旧库迁移前完全一致。
- `regression/verify_v10.log`：最初完整验证在旧版库存视图 schema 处失败；`regression/verify_v10_v2.log`：修正视图后原校验 VFY01—VFY11 通过，VFY12 因源库遗留时间顺序问题报 51360，VFY12/13 未通过。
- `regression/verify_v10_roles.log`：独立 VFY14 权限检查 PASS。
- `regression/legacy_anomalies_source.log` 和 `legacy_anomalies_target.log`：旧数据不变量异常两库一致，依次为 20、402、225、1。
- `regression/actual_fks.txt`：18 条启用 FK 对应父表/子表/外码列，供 week6 ER QA 交叉核对。

**说明**：原始 v0.1 数据继承的 VFY12/13 异常没有被“迁移成功”掩盖。所有数据库字段值核对均避开密钥与密码哈希列，负例修改事务后回滚。

## Python/图表补充证据

- `regression/qa_week6.log`：15 实体/18 实际 FK、一致性、SVG/PNG 和 56 条文档链接均 PASS。
- `regression/python_unit_tests_v2.log`：22 项 Python 测试中 12 通过，10 因未指定隔离数据库而 skipped。首次 PowerShell 将 stderr 当作错误中止的尝试保留为记录，但不作为测试通过凭据。
- `regression/syntax_check.py`：Python 语法检查工具，2 个第六周 Python 文件 AST 检查通过；电脑无可用 Ruff 命令/仓库 .venv，未执行 Ruff。

## 第五周问题修复的 v1.1 独立副本

[修复内容与未决事项](../../week6/v11/README.md)、[v1.1 测试日志索引](issue_fixes/README.md)。这是在 v1.0 之外追加的约束与管理事务验证，**不是覆盖第六周原迁移结果**。

## 从迁移前完整代码独立复现

见 [第六周历史代码归档](../../archive/week6-pre-migration/README.md)、[自动复现脚本及命令](../../week6/reproduction/README.md)、[实际两轮复现日志](reproduction/README.md)。从历史 Git 版本 `c8d4e64` 的 344 个文件重新创建 v0.1 并迁移成功，自动脚本运行 R01–R12、VFY01–VFY14 全部通过，非权限业务基准 3763 条零差异。此结果仅属于新建的标准样例库，不代表历史 v0.1_A 的异常已清洗。
