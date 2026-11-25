# 第13周正式复现批次 WebW13Run03

- [从空库构建清单](../../webapp/WebW13Run03/manifest.json)：第10—12周均已安装，第13周共用供应商锁随第12周事务安装。
- [双会话记录](concurrency.jsonl)：同行写等待、脏读对照、不可重复读对照、死锁及同序重放、实际业务等待与竞购全部通过。第13周等待记录以 `*.blocked` 标记。
- [全量 unittest](full_unittest.log)：126 项通过，0 失败、0 跳过。在并发测试前运行。
- [触发器](test_trigger.log)、[窗口查询](window_query.log)、[递归查询](recursive_query.log)、[事务回归](test_transactions.log)、[分类维护](test_category_maintenance.log)：并发测试后的逐项 SQL 结果。
- [清理预览](cleanup_preview.log)与[清理核验](cleanup.log)：本批次三个数据库及备份已删除，证据保留。
- [第13周报告](../../../report/week13_report.md)说明锁与业务数据的对应关系，第10—13周综合交付见[第三阶段报告](../../../report/stage3_report.md)。

SQL 结果文件去除了列尾填充空格，触发器记录中的本机登录名已脱敏；A2 的原查询仍核验它与 `ORIGINAL_LOGIN()` 一致。

旧事务未持有共用入口锁的反例为 [57114](../WebW13Run01/red_business_gate_check.log)。同批次保留调试过程：初次夹具遗漏补货必填字段；死锁记录补采集异常事务状态；旧库增量补齐 SQL 会话选项；拆开 ODBC 参数批次与外层 BEGIN；最后把入口锁移到余额范围锁前。中间版从空库的[全量回归](../WebW13Run02/full_unittest.log)与正式批次分开保存。
