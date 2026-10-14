# 第五周 I01–I10 问题修复进度（v1.1 隔离副本）

**数据库**：`TokenHubDB_v11_Issues_20261014`（从 v1.0 独立备份并还原）；原 `TokenHubDB_v01_A` 和 `TokenHubDB_v10_W6_20261014` 未改。此处只记录**已部署并测试通过的控制**，没有将未定业务规则改成既定需求。

## 1. 当前状态

| 编号 | 已实施及测试的范围 | 未解决/需决定的部分 |
|---|---|---|
| I01 订单至少含明细 | 支付/退款订单必须至少有一条明细，且汇总金额、Token 与明细相符；支付后明细不可直接变更。正反例 PASS | pending 草稿仍可暂时没有明细。若所有状态都严格要求 1..*，应改为“单存储过程创建订单头+明细”并封闭直接订单 INSERT，避免父表先插入时被约束拒绝 |
| I02 同单同商品重复 | **已确定并实施**：保留 `UQ_OrderDetails_order_product`；`usp_W5_AddMergedOrderItem` 对同商品累加 `quantity`，保留首次成交快照并同步汇总 | 不允许以两条记录保存不同成交价；数量合并使用受控过程 |
| I03 散客购买 | **已确定并实施**：下单前必须存在活跃 `Users` 记录；`Orders.user_id NOT NULL` 和 FK 保留，`usp_W5_CreateRegisteredOrder` 拒绝不存在的用户 | 不支持无用户记录的匿名订单；注册/身份校验属于用户模块，不在测试中伪造账户凭据 |
| I04 每账号必有库存 | **已确定并实施**：新建 `UpstreamAccount` 自动生成一行 `Inventory`，禁止删除或改绑库存后遗留无库存账号；原有 `Inventory.account_id UNIQUE` 保证最多一行 | 正常事务内保证父→子 1..1；上游额度与库存一致性的其它直接修改路径仍需治理 |
| I05 调用 provider/时间区间 | `trg_W5_UsageNewValidity` 检查新增/修改调用行的注册时间、provider、账号创建和到期边界；负例 PASS | 旧库继承的 225 条上游有效性/provider 异常未修复；对已存在账号/商品/用户元数据的独立修改仍需额外防护 |
| I06 跨表汇总 | 已支付订单头和明细对账，已支付明细不可改；`usp_W5_RecordUsage` 同事务更新会员余额、上游已用配额、库存、消费/库存流水和日/周/月汇总，正例及回滚 PASS | 其他直接更新订单头、上游配额/库存、支付充值等路径尚未统一成受控事务 |
| I07 自动补货创建人 | **已确定并实施**：新增 `created_source`，默认 `manual`；人工必须有 `created_by`，系统任务 `created_by=NULL`，使用可信 CHECK + FK | 原有补货任务迁移为 manual；`assigned_to` 仍可空 |
| I08 弱引用 | 对新库存流水中 order/restock_task 引用、新异常日志中 Orders/Inventory/TokenUsageLogs 引用进行有效性检查；引用对象 DELETE 保护；负例 PASS | `InventoryLog.reference_type=manual` 的既有 3000 个非空参考号语义尚不明确，未强行改为 FK。动态引用依靠触发器而不是静态外码 |
| I09 历史余额 | `usp_W5_RecordUsage` 余额不足/额度不足阻止新增调用；事件与余额扣减使用同一事务；普通管理员直接修改调用流水被拒；测试 PASS | 源库遗留的 1 次历史负余额仍存在；支付充值及经理直接余额 DML 尚不能证明都走统一事件账本 |
| I10 角色区分 | 应用 Roles 与 SQL Server 的 hub_* ROLE 仍分离；原 v1.0 R01–R12 通过。新增管理入口仅 grant 给 hub_manager，经理直接写调用流水需改走存储过程 | 未来会员调用应由经过身份映射的应用服务调用，不应直接把可自选 user_id 的 `usp_W5_RecordUsage` 授权给 hub_customer |

## 2. 文件与执行证据

| 功能 | 文件 |
|---|---|
| 独立副本备份/还原（拒绝覆盖） | [prepare_sandbox.sql](prepare_sandbox.sql)、[copy.log](../../result/week6/issue_fixes/copy.log) |
| I01、I05、I08 的新写入约束 | [enforce_known_rules.sql](enforce_known_rules.sql)、[test_guards.sql](test_guards.sql) |
| I06、I09 受控调用事务 | [record_usage.sql](record_usage.sql)、[test_managed_usage.sql](test_managed_usage.sql) |
| 审计目标删除保护/普通管理员直写拦截 | [protect_parent_deletes.sql](protect_parent_deletes.sql)、[test_parent_and_role.sql](test_parent_and_role.sql) |
| 功能测试日志 | [test_guards_02.log](../../result/week6/issue_fixes/test_guards_02.log)、[test_managed_usage_02.log](../../result/week6/issue_fixes/test_managed_usage_02.log)、[test_parent_and_role_01.log](../../result/week6/issue_fixes/test_parent_and_role_01.log) |
| 原 v1.0 R01–R12 兼容性回归 | [regression_v11.sql](regression_v11.sql)、[regression_v11.log](../../result/week6/issue_fixes/regression_v11.log) |
| 完成后业务数据对照 | [v11_semantics_after_tests.txt](../../result/week6/issue_fixes/v11_semantics_after_tests.txt)：与原 v1.0 的 3,763 条非权限业务结果零差异 |

历史测试中 `test_guards_01.log` 曾被原有 `ExceptionLog.exception_type` CHECK 拦截；修正输入后 `test_guards_02.log` PASS，旧失败记录保留。

## 3. 已确认的业务选择（2026-10-14）

- **I02**：同一订单的同一商品合并为一行，增加 `quantity`；不允许同单多条不同价格的同商品明细。
- **I03**：必须先有 `Users` 记录才可下单；不支持不关联用户记录的匿名订单。
- **I04**：每个上游账号在事务提交时有且仅有一行 `Inventory`；建立账号时自动初始化，不得单独删掉库存。
- **I07**：`created_source='manual'` 时 `created_by` 必填；`created_source='system'` 时 `created_by=NULL`。

**实施文件**：[approved_rules.sql](approved_rules.sql)、[registered_order_workflow.sql](registered_order_workflow.sql)、[test_approved_rules.sql](test_approved_rules.sql)；[部署及测试日志](../../result/week6/issue_fixes/README.md)。[v1.1 可编辑 ER 源](er_diagram_v11.mmd)、[SVG](er_diagram_v11.svg)、[PNG](er_diagram_v11.png) 根据最新基数重新导出，独立保留 v1.0 源图。

还需单独决定历史异常的数据修复依据：当前源库及复制结果中的“早于注册”订单 20、调用 402、上游有效性错配 225、历史负余额 1，必须以可信业务事件来源为准，不能凭猜测调整时间或金额去制造零异常。

**边界**：目前脚本已作用于独立 v1.1 副本，但没有修改或清洗 v0.1/v1.0 业务数据，没有自动 commit/push。本轮对 I01、I05、I06、I08、I09 实施的是限定场景的前向防护，不把它们全部说成闭环。
