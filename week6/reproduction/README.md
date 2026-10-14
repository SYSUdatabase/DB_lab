# 第六周：从迁移前完整代码快照重新复现 v0.1 → v1.0

## 一、独立输入及版本

1. **迁移前完整代码**：[`DB_lab_pre_week6_c8d4e64_full_source.zip`](../../archive/week6-pre-migration/DB_lab_pre_week6_c8d4e64_full_source.zip)，来自历史 Git 提交 `c8d4e64`（第六周首次提交 `43b5112` 的父提交）。包含当时 **344 个 Git 跟踪文件**，包含建库、样例、DDL/约束、视图/查询、角色、测试、生成器、第五周 ER 图、项目说明及旧证据。
2. **校验值**：SHA-256 `D2DFA2F23504050ACBA3F4BDE95A7946DCA72D29F6599A6D75A67C16DDE5743C`；完整 Git 对象与路径清单见 [source_manifest.txt](../../archive/week6-pre-migration/source_manifest.txt)，ZIP 永远不原地修改。
3. **第六周迁移实现**：当前仓库 [migration.sql](../../sql/migration.sql) 与 [regression.sql](../../sql/regression.sql)，及 [v1.0 VFY01–VFY14](../verify_v10.sql)。此脚本在运行前复制一份到新日志目录，再将里面原本写死的数据库名替换为**全新测试库名**；不直接改动权威源码。
4. **SQL Server**：需要支持备份/还原、`EOMONTH`、`DATETIME2`、角色权限及 SQLCMD 的 SQL Server 实例，并能以 Windows 集成身份连接（`sqlcmd -E -C`），有建库/备份/还原的相应权限。测试环境为 sh 电脑的 `localhost\SQLEXPRESS`。
5. **备份界限**：ZIP 是**完整历史 Git 跟踪代码与课程文件**，不包含原 SQL Server 的 MDF/LDF/BAK、未被 Git 跟踪的本地文件、`.git` 历史数据库或登录凭据。迁移会先由旧代码生成一份数据库，之后执行数据库备份/还原。

## 二、复现命令

在 `D:\Desktop\DB\DB_lab` 中运行：

```powershell
# 必须使用新的、6—16 位字母数字后缀。不能复用已有数据库/目录。
powershell -NoProfile -ExecutionPolicy Bypass -File .\week6\reproduction\run_from_snapshot.ps1 -Server 'localhost\SQLEXPRESS' -Suffix 'W6ReplayNew001'
```

脚本每次都会：
1. 比对历史 ZIP 的 SHA-256，检查源/目标库名、备份物理路径、工作目录、日志目录**尚未被使用**；遇到冲突即终止，**不删除、不覆盖**。
2. 解压快照到仓库旁边新目录 `D:\Desktop\DB\DB_lab_replay_<Suffix>`；验证 344 文件。
3. 调用该解压目录内的**旧版** `tools/run_v01.ps1`，在全新 `TokenHubDB_v01_<Suffix>` 上执行 `00_create_database.sql`、建表、数据/CRUD、视图、查询、约束、角色、`verify.sql` 与签名（所有操作发生在新库）。不启用 `-DropExisting`。
4. `BACKUP ... COPY_ONLY, CHECKSUM` 与 `RESTORE VERIFYONLY`，独立还原到 `TokenHubDB_v10_<Suffix>`；同时保存恢复前源/副本的只读业务基准，校验 SHA-256 相等。
5. 从 `sql/migration.sql` 制作目标名受限的临时脚本，在还原副本进行 **UsageSummary → UsagePeriod + UsageSummaryCore** 的事务性迁移（15 表、18 FK、11 视图、99 个周期定义、3394 条汇总）。
6. 从 `sql/regression.sql` 与 `week6/verify_v10.sql` 派生只作用于此源/副本的验收脚本，执行 **R01–R12** 及 **VFY01–VFY14**，任何非零退出码或缺失最终 PASS 标记即停止。
7. 再次获取目标的只读业务基准，排除按计划新增的**数据库权限行**后，核对 **3763 行非权限业务记录零差异**，输出最终复现记录与证据文件。

**新库名**由同一 `Suffix` 自动组合；SQL Server 备份/MDF/LDF 由该实例默认目录分配**新名称**，失败后不自动清理、回滚其他已成功阶段或覆盖历史输出。重新运行必须使用**新的 Suffix**，或由用户另行批准清理测试副本。

## 三、已实际复现的结果

| 本轮 | v0.1 来源 | 迁移副本 | 实际结果 |
|---|---|---|---|
| 第一次分步核验 | `TokenHubDB_v01_W6Replay261014` | `TokenHubDB_v10_W6Replay261014` | 旧代码重新建库 PASS，备份与副本基准 hash 相同，迁移 PASS，R01–R12 PASS，VFY01–VFY14 PASS |
| 第二次自动脚本核验 | `TokenHubDB_v01_W6Auto261014` | `TokenHubDB_v10_W6Auto261014` | `run_from_snapshot.ps1` 从 ZIP 到全套校验完整执行，3763 条非权限基准记录零差异 |

- 第一次分步核验文件：[reproduction 证据](../../result/week6/reproduction/README.md)；自动核验文件：[`W6Auto261014/`](../../result/week6/reproduction/W6Auto261014/replay_manifest.txt)。
- **代码快照生成的标准 v0.1 有 10 个视图**；此前实际本地 `TokenHubDB_v01_A` 只有 9 个。现行 `migration.sql` 增加前置判断，同时支持这**两种已查证的视图基线**；其它不符结构仍拒绝迁移。标准代码路径不再错误地尝试重复创建 `v_CustomerService`。
- 新生成的历史样例中，原 `verify.sql` 及迁移后的 VFY12/VFY13 通过；原 `TokenHubDB_v01_A` 里的旧历史异常依然存在，**不是因为规范化而被修正**。以上两个数据来源必须分别描述，不能复用它们的日志混写为同一次结果。

## 四、复现边界与后续

- 已完整验证 **第六周 ch7 主体迁移（v0.1 → v1.0）**，不依赖原 `TokenHubDB_v01_A` 的数据库内容。
- 第五周 I01–I10 在 v1.1 上的后续业务约束修复仍保留在 [issue_fixes](../issue_fixes/README.md)；此一键脚本不擅自将这些后续约束加入第六周规范化事务。
- 正例/反例测试可能推进隔离数据库的 IDENTITY 计数，但业务行均按测试代码回滚。全套业务基准以 **集合对账** 判定，不保证数据库文件的字节级一致。
- ZIP 可能包含课程历史证据，未经单独审查不建议公开传播。程序不读取/输出私钥、CDKey、密码哈希或数据库备份字节；只用项目 SQL 的结构、生成的样例及非敏感业务基准核验。
