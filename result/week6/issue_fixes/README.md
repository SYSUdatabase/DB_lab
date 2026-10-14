# v1.1 第五周遗留问题修复测试日志

目标数据库：`TokenHubDB_v11_Issues_20261014`。只在独立副本安装后续约束。原 v0.1、v1.0 未修改。

| 文件 | 含义 |
|---|---|
| `copy.log` | 从现有 v1.0 COPY_ONLY + CHECKSUM 备份，RESTORE VERIFYONLY 后独立还原 |
| `enforce_known_rules.log` | 5 个订单/新增调用/弱引用触发器部署 PASS |
| `test_guards_01.log` | 首次测试使用不允许的异常类型，失败记录保留 |
| `test_guards_02.log` | 修正后 6 个订单/调用/引用正反例 PASS |
| `record_usage_install.log` | 原子化消费过程安装 PASS |
| `test_managed_usage_01.log` | 余额、上游额度、库存、调用、库存日志、周期汇总事务与回滚 PASS |
| `protect_parent_deletes_install.log` | 阻止悬空目标删除与普通管理员直接写事件的触发器安装 PASS |
| `test_parent_and_role_01.log` | 管理员绕开调用过程、删除被审计引用订单/任务的反例均按预期拒绝 |
| `test_managed_usage_02.log` | 第二批触发器部署后原子事务/余额不足反例仍 PASS |
| `regression_v11.log` | 原第六周核心 R01–R12 在 v1.1 副本全部 PASS |
| `v11_semantics_after_tests.txt` | 与 v1.0 的 3763 条非权限业务记录差异为 0 |

上述测试中的插入或更新正例均以事务回滚；测试过程中 IDENTITY 计数可能前进，但未写入额外业务行。详细状态与未解决业务选择见 [修复说明](../../../week6/issue_fixes/README.md)。历史异常仍与复制来源一致，不能当作已清洗。

## 用户批准 I02/I03/I04/I07 后的增量

- `approved_rules_install_01.log`、`approved_rules_install_02.log`：首次两个部署尝试因同批次引用新增的 created_source 列而报 207。两次均已完整回滚，留存失败证据。
- `approved_rules_install_03.log`：增加批次分隔后成功；RestockTask 字段、可信 CHECK/FK 与三个新触发器全部部署。
- `registered_order_workflow_install_01.log`：注册用户下单及合并订单明细两个受控过程创建成功。
- `test_approved_rules_01.log`：首次六类正反例 PASS；`test_approved_rules_02.log`：追加同单同商品直接重复插入的 UNIQUE 负例，再次全部 PASS。
- `verify_approved_rules.log`：15 物理表、18 可信 FK、13 个新旧触发器、既有 8 个上游账号/8 条库存、8 条旧 manual 补货任务与新增约束的只读检查通过。
- `test_guards_postapproval.log`、`test_managed_usage_postapproval.log`、`test_parent_and_role_postapproval.log`、`regression_v11_postapproval.log`：原有四组 v1.1/v1.0 正反例与 R01–R12 复测全部 PASS。
- `approved_business_after.txt`：两侧各 3763 条非权限业务记录，相对于 v1.0 基准 **0 条差异**；所有模拟插入在测试事务中回滚。
- [v1.1 业务规则与数据库差异](../../../week6/issue_fixes/data_dictionary_v11.md)、[可编辑 ER](../../../week6/issue_fixes/er_diagram_v11.mmd)。

## 最终自检

`week6/issue_fixes/qa_approved_rules.py` 对照数据库 FK 导出记录，验证 15 张表、18 条实际 FK、最新基数和 v1.1 SVG/PNG 均通过；旧 week5/week6 ER QA 通过。最后文档自检检查 133 条相对链接，0 失效，`git diff --check` 通过。不会覆盖 v1.0 数据库或已经保存的失败日志。
