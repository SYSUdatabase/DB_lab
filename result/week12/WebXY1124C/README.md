# 第12周商品分类自动维护首轮复测（WebXY1124C）

本批次用于首次验证商品分类自动维护修改。新库从空库构建至第12周，分类自动维护、触发器、事务和只读查询均通过；本批次不是最终全量验收批次。

| 检查 | 结果 | 证据 |
|---|---|---|
| 商品分类自动维护 | 6/6 通过 | [category_maintenance.log](category_maintenance.log) |
| 第11周触发器 | 14/14 通过 | [test_trigger.log](test_trigger.log) |
| 第12周事务 | 14/14 通过 | [test_transactions.log](test_transactions.log) |
| 窗口查询 | 退出码 0 | [window_query.log](window_query.log) |
| 递归查询 | 退出码 0 | [recursive_query.log](recursive_query.log) |
| 首次全量 unittest | 126 项运行，其中 13 项跳过 | [full_unittest.log](full_unittest.log) |

首次全量运行时，构建过程结束后已移除临时 `DB_LAB_DEMO_PASSWORD` 环境变量，导致依赖该变量的 13 项员工/Web 集成测试被跳过。因此该批次不作为最终全量验收结果。随后在 WebXY1124D 中将同一临时密码变量贯穿建库和测试，最终 126 项全部通过、0 跳过，见[最终复测](../WebXY1124D/README.md)。

清理：WebXY1124C 的三个测试数据库及 SQL 备份已由 `cleanup_reproduction.ps1 -KeepEvidence` 删除并核验 PASS；本目录和构建证据保留。
