# v0.1 结果与证据索引

本目录保存第一阶段第 1～4 周整合后的真实执行证据。日志来自 `sqlcmd`，截图来自 sh 电脑上对 `TokenHubDB_v01_A` 的实时 SQL Server 查询窗口抓屏，不使用模拟结果图。

## 1. 目录说明

- `dev/`：分步开发验证日志。
- `run_A/`：`TokenHubDB_v01_A` 首次完整空库复现。
- `run_B/`：`TokenHubDB_v01_B` 第二次完整空库复现。
- `repeat_A/`：A 库重复执行第四周脚本后的幂等性验证。
- `evidence_sql/`：用于生成结果截图的只读/事务化证据 SQL。
- `evidence_logs/`：12 组证据 SQL 的原始执行输出。
- `screenshots/`：课程提交用真实结果截图。

## 2. 第一至四周证据映射

| 周次 | 要求 | 证据位置 |
|---|---|---|
| 第 1 周 | 经营场景、角色、业务流程、数据边界 | `../week1 & 2/week1_deliverables.md`、`../README.md`、阶段报告第 1 节 |
| 第 2 周 | 关系模式、字段、主码/候选码/外码、样例元组 | `../week1 & 2/week2_deliverables_v2.md`、`../sql/01_create_tables.sql` |
| 第 3 周 | 建库、样例数据、CRUD、非法数据、一致性 | 截图 01～04、08～09，`run_A/00`～`03` 与 `verify.sql.log` |
| 第 4 周 | 查询、视图、约束、角色与权限 | 截图 05～11，`query/view/constraint/role` 日志 |
| 阶段验收 | 双空库复现和结果一致 | 截图 12、`run_A/`、`run_B/`、`repeat_A/` |

## 3. 截图清单

| 文件 | 内容 | 结论 |
|---|---|---|
| `screenshots/01_database_tables.png` | A 库、14 张表、各表行数、9 视图/4角色/5用户 | PASS |
| `screenshots/02_crud_products.png` | Products INSERT / UPDATE / DELETE 前后结果 | PASS |
| `screenshots/03_crud_inventory.png` | UpstreamAccount + Inventory CRUD | PASS |
| `screenshots/04_crud_orders.png` | Orders + OrderDetails CRUD | PASS |
| `screenshots/05_join_query.png` | Q01 四表 JOIN 与 184 条明细 | PASS |
| `screenshots/06_sales_members.png` | Q02 商品销量/销售额、Q05 无 paid 订单会员 | PASS |
| `screenshots/07_statistical_views.png` | 四个核心统计视图及汇总结果 | PASS |
| `screenshots/08_constraint_legal.png` | C01/C02 合法值、DEFAULT/NULL | PASS |
| `screenshots/09_constraint_illegal.png` | C05/C06/C08 错误 547 与具体约束名 | PASS |
| `screenshots/10_role_allowed_denied.png` | guest/staff/manager 权限、R04 越权拒绝、R05 合法更新 | PASS |
| `screenshots/11_customer_isolation.png` | hub_user_1 / hub_user_2 仅看到本人数据 | PASS |
| `screenshots/12_reproduction.png` | A/B 两库 14 表逐表行数与 SHA-256 签名比较 | PASS |

截图对应 SQL 位于 `evidence_sql/`；同名原始输出位于 `evidence_logs/`，可用于复核截图不是手工填写结果。

## 4. 原始日志索引

| 能力 | 脚本 | 主要日志 |
|---|---|---|
| 建库建表 | `sql/00`、`01` | `run_A/00_create_database.sql.log`、`01_create_tables.sql.log` |
| 样例数据 | `sql/02_insert_data.sql` | `run_A/02_insert_data.sql.log` |
| CRUD | `sql/03_crud_demo.sql` | `run_A/03_crud_demo.sql.log` |
| Q01～Q08 | `sql/query.sql` | `run_A/query.sql.log` |
| 9 个视图 | `sql/view.sql` | `run_A/view.sql.log` |
| C01～C11 | `sql/constraint.sql` | `run_A/constraint.sql.log` |
| R01～R13 | `sql/role.sql` | `run_A/role.sql.log` |
| VFY01～VFY11 | `sql/verify.sql` | `run_A/verify.sql.log` |
| 14 表签名 | `sql/signature.sql` | `run_A/signature.txt`、`run_B/signature.txt` |
| 重复执行 | view/constraint/role/verify | `repeat_A/` |

`sqlcmd -u` 生成的主流水线日志为 Unicode；截图证据查询另有 `evidence_logs/`。CRUD 与截图证据中的临时写操作均使用事务回滚，未改变基础样例数据。

## 5. 当前证据结论

A/B 两个空库的 14 张业务表内容签名完全一致；A 库重复执行第四周脚本后签名仍一致。正常访问、非法数据、越权访问、会员隔离、统计视图、CRUD 和关键查询均已有日志与 PNG 截图双重证据。
