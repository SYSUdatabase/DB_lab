# v0.1 结果与证据索引

本目录保存第一阶段第 1～4 周整合后的真实执行证据。日志来自 `sqlcmd`；`screenshots/` 中的 PNG 抓屏于 2026-09-30、sh 电脑上的实时 SQL Server 查询窗口，不使用模拟结果图。

## 1. 目录说明

- `run_A/`：`TokenHubDB_v01_A` 完整空库复现（2026-10-01，修订后脚本）。
- `run_B/`：`TokenHubDB_v01_B` 完整空库复现，同上。
- `run_C/`：`TokenHubDB_v01_C` 完整空库复现，同上。
- `evidence_sql/`：用于生成结果截图的只读/事务化证据 SQL。
- `evidence_logs/`：22 组证据 SQL 的原始执行输出。
- `screenshots/`：提交用真实结果截图（01～12 为 2026-09-30 抓屏，13～22 为 2026-10-01 抓屏）。
- `第3周人工测试演示结果.pdf`：第三周人工复测记录（2026-09-25）。

## 2. 第一至四周证据映射

| 周次 | 要求 | 证据位置 |
|---|---|---|
| 第 1 周 | 经营场景、角色、业务流程、数据边界 | `../week1 & 2/week1_deliverables.md`、`../README.md`、`../report/stage_report.md` |
| 第 2 周 | 关系模式、字段、主码/候选码/外码、样例元组 | `../week1 & 2/week2_deliverables_v2.md`、`../sql/01_create_tables.sql`、`../report/stage_report.md` 第 1 节 |
| 第 3 周 | 建库、样例数据、CRUD、非法数据、一致性 | 截图 01～04、08～09、19～20，`run_A/00`～`03` 与 `verify.sql.log`，`第3周人工测试演示结果.pdf` |
| 第 4 周 | 查询、视图、约束、角色与权限 | 截图 05～11、13～18，`run_A/query.sql.log`、`view.sql.log`、`constraint.sql.log`、`role.sql.log` |
| 阶段验收 | 多空库复现和结果一致 | 截图 12、21、22，`run_A/`、`run_B/`、`run_C/` |
| 2026-10-01 修订 | 客服视图、库存状态拆分、新增查询/约束/权限用例 | 截图 13～22，`run_A/`～`run_C/` 的 `view.sql.log`、`query.sql.log`、`constraint.sql.log`、`role.sql.log`、`verify.sql.log` |

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
| `screenshots/13_customer_service.png` | R14 `v_CustomerService` 无敏感列且店员可读、R15 店员读 `dbo.Users` 报错 229、R16 会员读该视图报错 229 | PASS |
| `screenshots/14_inventory_states.png` | `v_InventoryStatus` 的 `account_state`/`stock_state`/`quota_headroom` 与 `InventoryLog` 变动类型 | PASS |
| `screenshots/15_q09_low_stock.png` | Q09 低库存边界行产生后事务回滚，基线行数不变 | PASS |
| `screenshots/16_q10_join_contrast.png` | Q10 INNER/LEFT JOIN 行数对比 10/10 与 26/40，含未被 paid 订单覆盖的会员 | PASS |
| `screenshots/17_q11_usage_trend.png` | Q11 日粒度 14 行、月粒度 3 行，日汇总与月汇总 token 数相等 | PASS |
| `screenshots/18_q12_consumption.png` | Q12 消耗/采购/补货分开统计，消耗最高账号为 account_id=7 | PASS |
| `screenshots/19_constraint_c12_c13.png` | C12/C13 候选码重复分别报错 2627，指向 `UQ_Products_provider_tokens` 与 `UQ_OrderDetails_order_product` | PASS |
| `screenshots/20_constraint_c14_json.png` | C14 非法 JSON 报错 547，`CK_Roles_permissions_json` 生效，库内 3 行 permissions 均 `ISJSON=1` | PASS |
| `screenshots/21_verify_all_pass.png` | 直接执行 `sql/verify.sql`，VFY01～VFY11 完整验收，11 项全部 PASS（该图证据 SQL 即 `sql/verify.sql`） | PASS |
| `screenshots/22_reproduction_abc.png` | A/B/C 三库 14 张表逐表 SHA-256 签名，14/14 MATCH | PASS |

截图对应 SQL 位于 `evidence_sql/`；同名原始输出位于 `evidence_logs/`，可用于复核截图不是手工填写结果。

> 截图口径说明：01～12 记录的是 2026-09-30 的脚本版本，其中显示“9 视图”、`stock_state` 单字段口径和 C01～C11、R01～R13。修订后的 10 视图、`account_state`/`stock_state` 拆分、Q09～Q12、C12～C14、R14～R17 由 13～22 这 10 张截图覆盖，均为 2026-10-01 在本机 SQL Server 上实时抓屏。

## 4. 原始日志索引

| 能力 | 脚本 | 主要日志 |
|---|---|---|
| 建库建表 | `sql/00`、`01` | `run_A/00_create_database.sql.log`、`01_create_tables.sql.log` |
| 样例数据 | `sql/02_insert_data.sql` | `run_A/02_insert_data.sql.log` |
| CRUD | `sql/03_crud_demo.sql` | `run_A/03_crud_demo.sql.log` |
| 10 个视图 | `sql/view.sql` | `run_A/view.sql.log` |
| Q01～Q12 | `sql/query.sql` | `run_A/query.sql.log` |
| C01～C14 | `sql/constraint.sql` | `run_A/constraint.sql.log` |
| R01～R17 | `sql/role.sql` | `run_A/role.sql.log` |
| VFY01～VFY11 | `sql/verify.sql` | `run_A/verify.sql.log` |
| 14 表签名 | `sql/signature.sql` | `run_A/signature.txt`、`run_B/signature.txt`、`run_C/signature.txt` |

`sqlcmd -u` 生成的主流水线日志为 Unicode；`signature.txt` 改为 UTF-8 且只含签名行，因此可用 `Compare-Object` 直接跨库比较。CRUD 与截图证据中的临时写操作均使用事务回滚，未改变基础样例数据。

## 5. 当前证据结论

2026-10-01 在本机构建的 A、B、C 三个空库，14 张业务表内容签名逐字节一致（截图 22 给出三库逐表 SHA-256 对照）。基础业务数据的未变更可从脚本本身核对：`sql/01_create_tables.sql` 与 `sql/02_insert_data.sql` 自第三周基线以来未改动，本轮修订只涉及视图、查询、约束用例、权限和验收脚本。正常访问、非法数据、越权访问、会员隔离、统计视图、CRUD 和关键查询均已有日志证据，22 项全部有 PNG 截图。
