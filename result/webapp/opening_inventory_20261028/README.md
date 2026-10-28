# 期初库存修复验收

目标库：`TokenHubDB_v11_Web261021D`。原缺口为账号14–17各100000000、账号63为1000000；修复只追加5笔期初流水，不更新现有额度、余额、订单及业务流水。清单见 `sql/app/opening_inventory_Web261021D.json`。

应用前已执行COPY_ONLY/CHECKSUM备份与RESTORE VERIFYONLY；成功备份位于SQL Server备份目录，文件后缀为 `55f2bcca585d4dfa9ecc06594062bedc.bak`。重跑迁移的备份后缀为 `921f2489abb048b690e5f55a37d702d5.bak`。备份不入Git。

- 回归先在旧过程失败：新建账号的期初流水行数预期1、实际0。
- 首次修复工具因SQLCMD包含指令使过程提取失败，数据库事务回滚；另一次因备份结果集未完整消费导致VERIFYONLY找不到文件。已修正过程定位、前置解析和结果集处理；保留失败说明，不将这些尝试记为成功备份。
- [tests.log](tests.log)：20项SQL、故障回滚及部署解析检查通过，含创建期初流水、未用账号删除、补货引用拒删、账号创建中途失败全表快照回滚，以及拒绝未知差额。
- [reapply.log](reapply.log)：重复执行待补记0笔，成功退出，没有重复流水。
- [reconciliation.log](reconciliation.log)：5笔期初流水及账号/库存/流水全量对账通过。
- [full_tests.log](full_tests.log)：60项测试，39项执行通过，21项skipped（未配置v0.1测试库和HTTP集成测试密码）。本轮未重建完整新应用库或重跑浏览器流程。
- `ruff check tools tests webapp`、变更Python文件 `ruff format --check` 与 `git diff --check` 通过。额外的仓库全目录Ruff扫描发现旧week6脚本与历史结果脚本20项既有格式问题，本轮未修改这些文件。

服务器普通Windows账户启动问题属于此前独立未完成事项，本修复不改变计划任务或凭据。
