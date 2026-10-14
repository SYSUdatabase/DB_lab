# 第六周 v1.0 数据字典与结构映射

**目标数据库**：`TokenHubDB_v10_W6_20261014`；由 `TokenHubDB_v01_A` 备份还原后的隔离副本规范化得到。迁移后的**物理表**共 15 张，**真实 FK** 共 18 条，视图 11 个。原 v0.1 数据库仍有 14 张表、17 条 FK、9 个视图（少于正式 view.sql 所定义的 10 个）。

## 1. 完整实体清单与主键/候选键

| 物理表 | 一行含义 | PK | 其它候选码/UNIQUE | FK |
|---|---|---|---|---|
| Roles | 一种应用角色 | role_id | role_name | — |
| Users | 一名注册用户 | user_id | username; email | — |
| Products | 一种可售套餐 | product_id | name; (model_provider,token_amount) | — |
| UpstreamAccount | 一个上游账号 | account_id | (provider,account_name) | — |
| Inventory | 某上游账号当前额度快照 | inventory_id | account_id | account_id→UpstreamAccount |
| Employees | 一个运营员工 | employee_id | account | role_id→Roles |
| Orders | 一张会员订单 | order_id | — | user_id→Users |
| OrderDetails | 一张订单的一种套餐购买明细 | detail_id | (order_id,product_id) | order_id→Orders; product_id→Products |
| InventoryLog | 一次额度增减事件 | log_id | — | account_id→UpstreamAccount; operator_id→Employees（可空） |
| TokenBalances | 用户某 provider 的余额快照 | balance_id | (user_id,model_provider) | user_id→Users |
| TokenUsageLogs | 一次用户/套餐/上游账号调用事件 | log_id | — | user_id→Users; product_id→Products; account_id→UpstreamAccount |
| **UsagePeriod（新增）** | 一个固定的 daily、weekly 或 monthly 周期定义 | **(period_type,period_start)** | — | — |
| **UsageSummaryCore（原 UsageSummary）** | 用户×套餐×固定周期的消费统计 | summary_id | (user_id,product_id,period_type,period_start) | user_id→Users; product_id→Products; **(period_type,period_start)→UsagePeriod** |
| RestockTask | 一个补货任务 | task_id | — | account_id→UpstreamAccount; created_by→Employees; assigned_to→Employees（可空） |
| ExceptionLog | 一条异常及处理记录 | exception_id | — | handled_by→Employees（可空） |

**重要**：`UsageSummary` 在 v1.0 中已是**只读兼容视图**，不是第 16 张物理表。其他 13 张旧表的字段、主键和外码保持 v0.1 原状；`UsageSummaryCore` 的原有主键、业务候选码和 Users/Products 外码保留。

## 2. 新旧字段映射

| v0.1 原字段 | v1.0 位置 | 规则 |
|---|---|---|
| UsageSummary.summary_id | UsageSummaryCore.summary_id | 主键数值完全不变 |
| UsageSummary.user_id,product_id | UsageSummaryCore 同名列 | 外码不变 |
| UsageSummary.period_type,period_start | UsageSummaryCore + UsagePeriod 同名列 | 两列表组成对 UsagePeriod 的可信 FK |
| **UsageSummary.period_end** | **UsagePeriod.period_end** | 同一类型+起点只保存一次 |
| UsageSummary.total_tokens_used,total_upstream_consumed,request_count,last_updated_at | UsageSummaryCore 同名列 | 历史指标和时间戳保持 |
| v0.1 dbo.UsageSummary 10 列读取 | v1.0 dbo.UsageSummary 视图 | 通过 UsageSummaryCore JOIN UsagePeriod 恢复原有 10 列，列顺序/类型/内容一致 |

**固定周期约束**：
- daily：`period_end = period_start`
- weekly：`period_start` 为周一，`period_end = period_start + 6 天`
- monthly：`period_start` 为当月第一天，`period_end = EOMONTH(period_start)`

`UsagePeriod` 主键 `(period_type,period_start)` + CHECK 保证周期定义的唯一性与合法性；`UsageSummaryCore` 的复合 FK 保证所有统计记录使用有效周期。当前物理结果：周期定义 **99** 行，汇总核心记录 **3394** 行。原 `period_end` 列及 CHECK 被移出核心表，新的复合 FK 经系统目录检查为已启用且可信。

## 3. 兼容性和权限边界

- 旧只读 SQL 的 `FROM dbo.UsageSummary` 仍能返回旧 10 列；`sql/query.sql` 中读周期的 Q11 和 `sql/verify.sql` 中 VFY10 的查询可以继续使用兼容视图。完整业务对账已用双向 `EXCEPT` 验证。
- **写入已变化**：旧的 `INSERT dbo.UsageSummary(...,period_end,...)` 和 `IDENTITY_INSERT dbo.UsageSummary ON` 不能再用于视图；新的合法路径是**先有 UsagePeriod 周期行，再向 UsageSummaryCore 插入/更新指标**。事务内用示例完成合法插入并回滚的证据见 `../result/week6/regression/regression_run_01.log` R05。v0.1 的生成器/旧正式 SQL **保持原样**，不能直接重新用于 v1.0 初始化数据。
- `hub_manager` 保留所有 15 张物理业务表的 SELECT/INSERT/UPDATE/DELETE，并可读兼容视图；`hub_staff` 没有新表直接权限，能够按正式 `sql/view.sql` 读取 `v_CustomerService`；会员/游客没有新增业务表或汇总视图访问权。R09–R11 已核对有效许可和拒绝。
- 源库 `v_CustomerService` 缺失，`v_InventoryStatus` 列不完整；v1.0 副本按正式 `sql/view.sql` 的已有定义补齐两者。修复只影响目标副本，不修改 v0.1。
- `OrderDetails` 的历史单价/Token 快照、公式 CHECK 和存储冗余保持；`RestockTask.created_by` 与 `assigned_to` 仍为两条独立外码。其他未决业务规则没有擅自修改。

## 4. 变更后验证边界

- `result/week6/regression/regression_run_01.log`：R01–R12 全部 PASS；旧汇总视图与源库内容、订单/销售/库存/余额/用量双向一致；合法写入/回滚、重复周期、周期 CHECK、缺失父周期 FK 及角色权限均通过。
- `result/week6/regression/legacy_anomalies_source.log` 与 `legacy_anomalies_target.log`：迁移前就有的四类旧数据异常，目标保持相同数量（20、402、225、1）；不将 VFY12/VFY13 标成 PASS。
- v1.0 ER 源 `er_diagram_v10.mmd`、导出 `er_diagram_v10.svg` / PNG 描绘 15 表/18 FK。**兼容视图不作为 ER 实体**，需在资料和说明中区分。
