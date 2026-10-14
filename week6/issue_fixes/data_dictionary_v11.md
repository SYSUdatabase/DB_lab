# v1.1 已批准业务规则与结构增量

作用库：`TokenHubDB_v11_Issues_20261014`，来自第六周 v1.0 副本；原 v0.1、v1.0 **不修改**。本增量不增加或删除物理业务表，仍有 **15 表、18 FK**。相较 v1.0 增加 3 个触发器与 2 个订单写入过程；v1.1 共 13 个 `trg_W5_*` 触发器。

| 编号 | 数据库实现 | 约束依据 | 结果 |
|---|---|---|---|
| I02 | 保留 `OrderDetails(order_id,product_id)` UNIQUE，`usp_W5_AddMergedOrderItem` 为待支付订单合并同商品数量 | 成交单价、token 档位采用该订单中首次记录的快照；总金额/总 Token 与明细同步更新 | 同商品两次 2 + 3 仅一条明细 quantity=5；直接插入第二条被 2601/2627 拒绝 |
| I03 | `Orders.user_id NOT NULL` + `FK_Orders_Users` 保留，`trg_W5_NewOrdersRegistered` 检查新订单的用户必须活跃且已注册；`usp_W5_CreateRegisteredOrder` 明确拒绝不存在或非活跃用户 | 允许先建立 Users 记录再下单，不允许无账户匿名订单；用户注册和凭证生成仍由认证模块负责，SQL 测试不读取实际密钥 | 无 Users 的直接 INSERT 被 FK 547 拒绝，存储过程被自定义错误 52123 拒绝 |
| I04 | `trg_W5_AutoInventoryOnAccount` 在同一个新账号 INSERT 事务中自动创建 Inventory；`trg_W5_PreventInventoryDetach` 拒绝删除/改绑导致父账号无库存。旧 UNIQUE(account_id) 保证最多一行 | 正常写入事务完成后，父 `UpstreamAccount`→`Inventory` 业务参与为 **1..1**，不是单靠外码即可保证 | 新账号总额度 100、已用 3 会自动创建 current_quota=97 的库存；删除唯一库存被拒。现存 8 个账号对应 8 条库存 |
| I07 | RestockTask 新增 `created_source VARCHAR(10) NOT NULL DEFAULT('manual')`，`created_by INT NULL`；可信 CHECK 限制 `manual→created_by NOT NULL`、`system→created_by NULL`；原员工 FK 重建且仍可信 | 系统创建不假装为员工；人工创建继续指向一个员工，`assigned_to` 仍可空 | 系统无员工和人工有员工均合法；反向两种非法组合均因 CHECK 547 被拒；现存 8 条补货任务保持 manual |

**关系基数补充：**
- 每条订单必须指向 1 个 Users，但一个用户可以有 `0..*` 个订单；
- 每条订单可包含不同商品的 `1..*` 条最终明细，同一商品只出现一条，数量记在 quantity；pending 草稿允许尚无明细；
- 一个 UpstreamAccount 在正常事务边界必须对应 1 个 Inventory，反向 Inventory 必须有 1 个 UpstreamAccount；
- 一条 RestockTask 创建人是 `0..1`（取决于 created_source），不再一律 1..1；人工来源必填、系统来源必须留空。

[可编辑 Mermaid ER 源文件](er_diagram_v11.mmd) → [SVG](er_diagram_v11.svg)、[PNG](er_diagram_v11.png)，通过 [渲染器](render_er_v11.py) 重新生成，未修改前版 v1.0 图。关系线可读性遵循第五周 ER 生成约定。

**部署顺序**：从 [v1.1 原有修复](README.md)（5 个触发器、原子化调用过程、另外 5 个审计保护触发器）继续执行 [approved_rules.sql](approved_rules.sql)，再执行 [registered_order_workflow.sql](registered_order_workflow.sql)。两个脚本都有数据库名和已安装对象检查，不能重复在现有副本执行；不是针对正式 v0.1/v1.0 的脚本。

**测试证据**：[规则正反例](../../result/week6/issue_fixes/test_approved_rules_02.log)、[结构验收](../../result/week6/issue_fixes/verify_approved_rules.log)、[原回归复测](../../result/week6/issue_fixes/regression_v11_postapproval.log)。前两次因 SQL Server 新增列与 CHECK 同批次编译报 207，均已事务回滚并保存失败日志；第三次分批后成功。

**仍未解决**：I05/I06/I08/I09 的所有可能直写路径闭环，以及源历史时间线/余额异常，需要基于真实来源单独处理。新的规则只防止可明确界定的错误继续被写入，不按推测修改历史数据。
