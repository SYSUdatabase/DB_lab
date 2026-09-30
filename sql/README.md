# `sql/` 阶段 SQL 说明

本目录是第一阶段 v0.1 的正式可复现 SQL 入口。脚本使用 SQLCMD 变量 `$(DatabaseName)`，默认由 `tools/run_v01.ps1` 传入数据库名。

## 执行顺序

```text
00_create_database.sql
→ 01_create_tables.sql
→ 02_insert_data.sql
→ 03_crud_demo.sql
→ query.sql
→ view.sql
→ constraint.sql
→ role.sql
→ verify.sql
→ signature.sql
```

## 第一至四周要求映射

| 周次 | 课程要求 | 本阶段对应文件 |
|---|---|---|
| 第 1 周 | 经营场景、角色、业务流程、数据边界 | `../README.md`、`../week1 & 2/week1_deliverables.md`、`../week4/stage_report.md` |
| 第 2 周 | 关系模式、字段、主码/候选码/外码、样例元组 | `01_create_tables.sql`、`02_insert_data.sql`、`../week1 & 2/week2_deliverables_v2.md` |
| 第 3 周 | 建库建表、样例数据、CRUD、可复现 | `00_create_database.sql`～`03_crud_demo.sql` |
| 第 3 周补充 | 非法数据与业务一致性 | 已并入 `constraint.sql` 与 `verify.sql`；历史脚本仍保留在 `../week3/sql/` |
| 第 4 周 | JOIN/聚合/子查询 | `query.sql` |
| 第 4 周 | 统计视图 | `view.sql` |
| 第 4 周 | 完整性约束正反例 | `constraint.sql` |
| 第 4 周 | 数据库角色与最小权限 | `role.sql` |
| 阶段验收 | 综合断言与双空库复现 | `verify.sql`、`signature.sql`、`../tools/run_v01.ps1` |
