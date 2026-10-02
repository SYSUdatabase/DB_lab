# 回归与重复执行记录

- tests_complete.log：最终 22 个 Python/SQL Server/证据工具测试全部通过，包含直接视图写授权反例。
- tests_final.log：补充视图写权限反例前的 21 个测试通过记录。
- verify_TokenHubDB_v01_FinalA/B.log：加入视图写权限检查后两个数据库的完整验收均通过。
- tests.log：新增引用反例前的 20 个测试通过记录。
- view/query/constraint/role/verify/signature.sql.log：重复执行当前阶段脚本的真实输出。
- signature_after_complete.txt：最终 22 个测试及最新权限验收后，14 表业务行签名仍与 run_final_A/signature.txt 一致；保留 sqlcmd 数据库上下文提示。
- signature_after.txt：重复执行和事务反例后业务行签名，与 run_final_A/signature.txt 一致。
- rejected_*.log：截图失败路径测试故意产生的 SQL 错误或 FAIL 标记，测试预期工具拒绝生成图片，不是正式流水线失败。
- visual_qa/：当前 26 张证据图片的内部检查联系表，不作为额外交付截图。

最终验收入口见 [当前结果](../README.md)。首次错误工作目录的失败测试日志保留在 archive/implementation-attempts，不计为通过。
