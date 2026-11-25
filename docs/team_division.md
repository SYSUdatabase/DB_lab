# 第三阶段小组分工（第10—13周）

项目：TokenHub 数据库编程与事务处理。仅记录第10周及之后的小组分工；更早的历史记录已归档。

| 部分 | 负责人 | 内容 | 证据 |
|---|---|---|---|
| 第10周存储过程与函数 | **陈诗翰** | 销售统计、库存调整、补货量函数、销售汇总函数和折扣业务；第10周结果核对 | [第10周SQL](../sql/week10/README.md)、[第10周报告](../report/week10_report.md) |
| 第11—12周主要实现与验收 | **肖懿** | 两个触发器、订单完成及补货入库事务、Web入口整合、并发复查与受限账户补验收 | [第11周报告](../report/week11_report.md)、[第12周报告](../report/week12_report.md) |
| 第11周窗口查询与触发器测试结果 | **陈诗翰** | `window_query.sql` 排名、累计值、移动平均；触发器测试与结果核对 | [窗口查询](../sql/week11/window_query.sql)、[触发器验证](../result/week12/WebXY1124D/README.md) |
| 第12周分类层级与递归查询、事务证据核对 | **阮依成** | 分类层级与递归查询、事务证据核对；人工发现新增/修改/删除商品未自动维护分类映射，要求修复并复验 | [递归查询](../sql/week12/recursive_query.sql)、[分类与事务验证](../result/week12/WebXY1124D/README.md) |
| 第13周并发控制 | **陈诗翰** | 双会话锁等待、隔离级别对照、死锁复现与同序取锁改进；订单与补货事务并发保护、竞购及回归验证 | [第13周报告](../report/week13_report.md)、[正式验收](../result/week13/WebW13Run03/README.md)、[修复复验](../result/week13/WebW13Fix01/README.md) |
| 第13周后业务测试与 Debug | **阮依成** | 复查第三阶段业务，发现上游额度耗尽账号补货后未恢复可用及 Web 冲突提示不够具体的问题，提出修复并组织回归验证 | [补货事务](../sql/week12/restock_transaction.sql)、[回归测试](../tests/test_restock_feedback.py)、[最终134项验收](../result/week13/WebW13Restock2/README.md)、[AI使用记录](ai_usage_log.md) |
| 第三阶段交付整理与历史归档 | **阮依成** | 整理第5—9周的 AI 使用记录、小组分工、实施计划和阶段报告至 `archive/`；精简 README、ROADMAP 及活动文档，突出第10周及以后交付 | [第二阶段归档](../archive/stage2/README.md)、[第三阶段入口](../README.md) |
