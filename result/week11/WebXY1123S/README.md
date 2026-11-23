# 第11周对齐讲义的修改与复测（WebXY1123S）

2026-11-23 按肖懿同意的方案做两项修改，代码其余部分不变：

- **“已完成（paid）”写法。** 数据库中的订单状态值仍为 `paid`；`trigger.sql` 的说明、第11周与第12周报告、两份测试脚本输出中的“预期结果/操作”文字统一写作“已完成（paid）”。测试输出中的“实际结果”列与订单状态清单直接取数据库值，仍显示 `paid`。
- **审计对应商品视图。** 新增视图 `w11.v_InventoryAuditProduct`（`sql/week11/trigger.sql` 末尾，随第11周安装），按“账号→供应商→该供应商的套餐”把每条审计展开为受影响的商品编号，一条审计对应该供应商的每个商品各一行；审计表不变。测试脚本新增用例 A7，核对视图行数等于“每条审计 × 该供应商商品数”且商品供应商与审计一致，并在结果记录中输出视图内容。

## 复测

数据库 `TokenHubDB_v11_WebXY1123S` 用 `tools/app_prepare.py --suffix WebXY1123S --with-week10 --with-week11 --with-week12` 从空 v0.1 新建，退出码 0。

| 项目 | 结果 | 证据 |
|---|---|---|
| 第11周触发器测试 | `SUMMARY\|14/14\|TRANCOUNT=0`，A1—A7、O1—O7 全部符合 | [test_trigger.log](test_trigger.log) |
| A7 视图映射 | 测试账号 #18、#19 共 5 条审计，A7 执行时 Other 供应商有 1 个商品，视图 5 行，供应商不一致或缺商品 0 行 | 同上 |
| 视图输出 | 结果记录在后续用例新建 3 个 Other 商品之后输出，此时同样 5 条审计展开为 20 行（每条审计对应 4 个 Other 商品） | 同上，“审计对应商品”一节 |
| 窗口查询 | 退出码 0 | [window_query.log](window_query.log) |
| 第12周事务测试 | `SUMMARY\|12/12\|TRANCOUNT=0` | [test_transactions.log](../../week12/WebXY1123S/test_transactions.log) |
| 递归查询 | 退出码 0 | [recursive_query.log](../../week12/WebXY1123S/recursive_query.log) |
| 全量 unittest | 124 项，OK，0 失败、0 跳过 | [full_unittest.log](../../week12/WebXY1123S/full_unittest.log) |
| 清理 | `tools/cleanup_reproduction.ps1 -Suffix WebXY1123S -KeepEvidence` 核验 PASS，数据库与备份已删除，证据保留 | — |

A7 执行时 Other 供应商只有 1 个商品，该用例本身体现的是“一条审计对应一个商品”的情形；一对多展开由结果记录中的视图输出（每条审计 4 行）体现。

## 待写入 AI 使用记录的内容（暂存）

AI 使用文档的修改正等待肖懿确认，本轮内容先记于此：AI 提出两项对齐讲义的修改，肖懿同意——数据库状态值保持 `paid`，文档与测试记录统一写“已完成（paid）”；新增视图把审计记录对应到受影响的商品编号，不改原表，测试覆盖该视图。按肖懿安排在受限账户验收之后实施。改动文件：`sql/week11/trigger.sql`（说明与视图）、`sql/week11/test_trigger.sql`（显示文字、A7、视图输出）、`sql/week12/test_transactions.sql`（显示文字）、`sql/week11/README.md`、`report/week11_report.md`、`report/week12_report.md`、`ROADMAP.md`。复测结果见上表。
