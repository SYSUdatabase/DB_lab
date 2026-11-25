# 第13周后业务修复完整验收 WebW13Restock2（2026-11-25）

阮依成复查第三阶段业务后提出两项修复：有效的 depleted 上游账号补货后应恢复 active，Web 应区分订单、补货及库存锁冲突。AI 辅助修改并在独立库回归。

| 验证范围 | 结果与证据 |
|---|---|
| 修复前反例与增量升级 | [WebW13Restock1](../WebW13Restock1/README.md)，升级后新增5项通过 |
| 从空库构建当前版本 | [prepare.log](prepare.log)，全部通过，包含大屏 |
| 全量 Python | [full_unittest.log](full_unittest.log)，134项通过，0失败、0错误、0跳过，115.045秒 |
| 并发控制 | [concurrency.jsonl](concurrency.jsonl)，5类场景全部通过 |
| 触发器、事务、分类 | [触发器14/14](test_trigger.log)、[事务14/14](test_transactions.log)、[分类6/6](test_category_maintenance.log)，事务计数均为0 |
| 高级查询 | [窗口](window_query.log)、[递归](recursive_query.log)，执行成功 |
| 静态检查 | [ruff.log](ruff.log)，检查通过、41个文件格式符合要求 |
| 临时批次清理 | [清理](cleanup.log)，三个测试数据库、两份备份删除并核实不存在；保留验收记录 |

专项测试覆盖状态恢复、暂停和到期限制、补货回滚及重复入库、Web 重复支付、空订单、可售额度不足、已关闭订单和补货单，以及新的库存锁繁忙提示。仅用 Flask 测试客户端验证 HTTP 响应与实际 SQL 交互，没有重新执行浏览器操作或普通 Windows 运行账户验收。本轮不改变顾客账号管理规则。触发器日志的本机 SQL 登录标识已脱敏。
