# 回归测试

使用根 README 中的 venv、ruff 与 unittest 命令。`test_timeline.py` 验证正常基线、注册前订单/调用、付款前透支、到期相等边界、provider 不匹配和无候选账号。SQL 集成测试只有显式指定 DB_LAB_TEST_DATABASE 时才运行，并只接受 TokenHubDB_v01_* 实验库名。

`test_sql_integration.py` 在事务中注入反例，执行正式 verify.sql 中对应检查段，必须命中指定错误号后回滚。最终余额保持不变的透支反例用于证明检查不依赖最终总量。缺单项 CRUD 和用户直接授予基表权限分别验证角色授权完整性与用户有效权限；直接对 customer 授予 v_MyOrders 的 UPDATE 权限必须触发 51368。

首次实现的空账号池曾抛 KeyError，已由无候选测试发现并修正为明确的 ValueError；测试覆盖这个边界以防复发。SQL 测试结束还须确认签名未改变，正常全量验收继续通过。

`test_evidence_tool.py` 使用故意 THROW 与 FAIL/PASS 混合输出，确认捕获工具非零退出且不生成图片。最终本机 22 个测试全部通过，原始输出位于 result/recheck/tests_complete.log。执行时必须以仓库为工作目录；一次从仓库外执行导致 tools 导入失败，已保留失败记录并在正确目录全量重跑通过。
