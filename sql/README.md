# `sql/` 阶段 SQL 说明

本目录是第一阶段 v0.1 的正式可复现 SQL 入口。脚本使用 SQLCMD 变量 `$(DatabaseName)`，默认由 `tools/run_v01.ps1` 传入数据库名。

## 执行顺序

```text
00_create_database.sql
→ 01_create_tables.sql
→ 02_insert_data.sql
→ 03_crud_demo.sql
→ view.sql
→ query.sql
→ constraint.sql
→ role.sql
→ verify.sql
→ signature.sql
```

视图先于查询：Q09 直接引用 `v_InventoryStatus`。`signature.sql` 单独执行时自行 `USE [$(DatabaseName)]`；由 `run_v01.ps1` 调用时输出只保留 `表名|行数|哈希` 三段式行，因此不同库名的签名文件可以直接逐字节比较。

## 脚本与规模

| 脚本 | 内容 | 规模 |
|---|---|---|
| `00_create_database.sql` | 建库、设置恢复模式；库已存在时抛 50001，绝不自动删库 | 1 个库 |
| `01_create_tables.sql` | 14 张业务表、主码、候选码、外码、CHECK 与默认值 | 14 表 |
| `02_insert_data.sql` | 固定随机种子生成的样例数据 | 40 用户 / 100 订单 / 184 明细 / 3000 调用 |
| `03_crud_demo.sql` | Products、UpstreamAccount+Inventory、Orders+OrderDetails 三组 CRUD，事务内回滚 | 3 组 |
| `view.sql` | 4 个经营统计视图 + 6 个权限用途视图 | 10 视图 |
| `query.sql` | JOIN、GROUP BY/HAVING、NOT EXISTS、CTE、子查询、事务内边界用例 | Q01～Q12 |
| `constraint.sql` | 约束盘点 + 3 个跨列 CHECK + 逐条正反例 | C01～C14 |
| `role.sql` | 4 个数据库角色、5 个演示用户、逐条正反例、权限审计 | R01～R17 |
| `verify.sql` | 逐表行数、跨表对账、逐行/逐键比对、权限矩阵复核 | VFY01～VFY11 |
| `signature.sql` | 14 张表完整内容 SHA-256 签名 | 14 行输出 |

## 固定样例口径

- 库存视图与 Q06/Q09 使用同一个样例快照时间 `2026-09-22T23:59:59`（样例数据窗口的最后一天），改动时两处要同步；写在 `view.sql` 顶部注释里。
- `verify.sql` 与 `signature.sql` 中的期望值（14 表、184 明细、40 用户、8 账号等）是样例数据的固定基线，不是业务常量；样例数据一旦重新生成，必须同步更新这些断言而不是放宽断言。
- `view.sql`、`constraint.sql`、`role.sql`、`verify.sql` 均为可重复执行脚本，重复运行不会改变基础业务数据。

## 第一至四周要求映射

| 周次 | 课程要求 | 本阶段对应文件 |
|---|---|---|
| 第 1 周 | 经营场景、角色、业务流程、数据边界 | `../README.md`、`../week1 & 2/week1_deliverables.md`、`../report/stage_report.md` |
| 第 2 周 | 关系模式、字段、主码/候选码/外码、样例元组 | `01_create_tables.sql`、`02_insert_data.sql`、`../week1 & 2/week2_deliverables_v2.md`、`../report/stage_report.md` 第 1 节 |
| 第 3 周 | 建库建表、样例数据、CRUD、可复现 | `00_create_database.sql`～`03_crud_demo.sql` |
| 第 3 周补充 | 非法数据与业务一致性 | 已并入 `constraint.sql`（C05/C06）与 `verify.sql`（VFY02、VFY05）；历史脚本仍保留在 `../week3/sql/` |
| 第 4 周 | JOIN/聚合/子查询 | `query.sql` |
| 第 4 周 | 统计视图 | `view.sql` |
| 第 4 周 | 完整性约束正反例 | `constraint.sql` |
| 第 4 周 | 数据库角色与最小权限 | `role.sql`、`../report/role_workflow.md` |
| 阶段验收 | 综合断言与多空库复现 | `verify.sql`、`signature.sql`、`../tools/run_v01.ps1` |
