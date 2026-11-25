# 第三阶段最终统一复验 WebW13Final01（2026-11-25）

在最新第13周修复代码上从空库构建独立批次，安装第10—12周对象（含第13周共用锁）与运营大屏。设置第10—13周测试数据库及原有 Web 集成测试环境变量，使用同一实验密码完成建库和测试；未修改已有业务库。

| 验证内容 | 结果 | 证据 |
|---|---|---|
| 从空库构建 | 全部安装步骤通过，含 dashboard | [prepare.log](prepare.log)、[构建清单](../../webapp/WebW13Final01/manifest.json) |
| Python 全量回归 | 129 项通过，0 失败、0 错误、0 跳过，107.802s | [full_unittest.log](full_unittest.log) |
| 第13周并发控制 | write_wait、dirty_read、repeatable_read、deadlock、competition 均 PASS | [concurrency.jsonl](concurrency.jsonl)、[运行日志](concurrency_run.log) |
| 第11周触发器 | 14/14，TRANCOUNT=0 | [test_trigger.log](test_trigger.log) |
| 第12周事务 | 14/14，TRANCOUNT=0 | [test_transactions.log](test_transactions.log) |
| 第12周分类维护 | 6/6，TRANCOUNT=0 | [test_category_maintenance.log](test_category_maintenance.log) |
| 窗口、递归查询 | 均正常退出 | [窗口](window_query.log)、[递归](recursive_query.log) |
| Ruff | 检查通过，40个文件格式符合要求 | [ruff.log](ruff.log) |
| 独立批次清理 | 三个测试数据库、两份备份及临时缓存已删除；保留证据 | [预览](cleanup_preview.log)、[清理结果](cleanup.log) |

实际竞购：商品98，每份需要9,980,318上游额度，两张不同订单154、155各购买6份。订单154成功，余额与发放批次 Token 均为550218，批次1条；订单155仍 pending，余额和批次均为0。最终物理可用上游额度101417019、已售未消耗额度61495747，差额39921272，恰为4份。与 WebW13Fix01 结果一致，但编号及样例额度属于本次独立批次。各轮测试均在专用库完成。

触发器日志中的本机 SQL 登录标识已脱敏，审计断言不变。没有重新执行完整浏览器流程或普通 Windows 运行账户验收；此前的相应证据仍保留。129项为本轮统一实测，不是旧126项与3项专项的相加。
