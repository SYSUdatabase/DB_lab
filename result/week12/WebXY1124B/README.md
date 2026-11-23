# 第11—12周终审修改后的复测（WebXY1124B）

2026-11-23 终审对照讲义发现第12周部分用例没有检查全部业务表，肖懿决定补齐。本批次在 87d96a7 的基础上只改了测试脚本 `sql/week12/test_transactions.sql`，过程、触发器和 Web 代码不变：

- T5 增加核对两张被拒订单的批次数与完成时间。
- R2 增加核对审计表，以及补货单的状态、实际量和入库时间不变。
- R4 增加核对总额度、流水和审计表不变。
- 新增 R6：已关闭（failed）的补货单入库返回 53312，库存、总额度、流水、审计与单据均不变。
- 新增 R7：53313（供应商无商品）的可达性核对。Products 与 UpstreamAccount 的供应商取值受 CHECK 限制为四个，被订单引用的商品不能改供应商（`trg_W6_ProductsHistory`）也不能删除；样例库中四个供应商都有被引用的商品，53313 在本库不可触发，本用例核对这一前提，不伪造场景。

## 复测

数据库用 `tools/app_prepare.py --suffix WebXY1124B --with-week10 --with-week11 --with-week12` 从空 v0.1 新建，退出码 0，各安装步骤 PASS（[日志](app_prepare.log)）。测试环境变量 `DB_LAB_TEST_DATABASE` 指向 `TokenHubDB_v01_WebXY1124B`，`DB_LAB_APP_DATABASE`、`DB_LAB_WEEK10_DATABASE`、`DB_LAB_WEEK12_DATABASE` 指向 `TokenHubDB_v11_WebXY1124B`，`DB_LAB_PREVIEW=1`。

| 项目 | 结果 | 证据 |
|---|---|---|
| 第11周触发器测试 | `SUMMARY\|14/14\|TRANCOUNT=0`，A1—A7、O1—O7 全部符合 | [test_trigger.log](test_trigger.log) |
| 窗口查询 | 退出码 0 | [window_query.log](window_query.log) |
| 递归查询 | 退出码 0，根、中间、叶子、不存在编号分别 9、5、1、0 行 | [recursive_query.log](recursive_query.log) |
| 第12周事务测试 | `SUMMARY\|14/14\|TRANCOUNT=0`，T1—T6、R1—R7、Z1 全部符合 | [test_transactions.log](test_transactions.log) |
| 第11—12周测试 | `python -m unittest tests.test_week11_12_sql -v`：9 项 OK | [week11_12_unittest.log](week11_12_unittest.log) |
| 全量测试 | `python -m unittest discover -s tests -v`：124 项 OK，0 失败、0 跳过 | [full_unittest.log](full_unittest.log) |
| 代码检查 | `ruff check webapp tests tools` 通过；`ruff format --check webapp tests tools` 38 个文件均已格式化 | [ruff.log](ruff.log) |
| 清理 | `tools/cleanup_reproduction.ps1 -Suffix WebXY1124B -KeepEvidence` 核验 PASS，三个数据库与两份备份已删除，证据保留 | — |

逐条的“初始数据—操作—预期结果—实际结果”见 [test_transactions.log](test_transactions.log) 与 [test_trigger.log](test_trigger.log) 中的结果集。新增与修改用例的实际结果：

| 用例 | 实际结果 |
|---|---|
| T5 | 53123、53125、53132；两张订单 pending，完成时间为空；余额不变；批次 0 |
| R2 | 53311；库存 108000、总额度 108000、流水 2、审计 2 不变；单据 completed，实际 8000，入库时间未变 |
| R4 | 53303、53303、53310；库存、总额度、流水、审计不变；单据 pending |
| R6 | 53312；库存 113000、总额度 113000、流水 3、审计 3 不变；单据 failed，实际量与入库时间为空 |
| R7 | 有被订单引用商品的供应商 4 个，53313 在本库不可触发 |
