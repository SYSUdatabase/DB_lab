# 第11周触发器验证记录（WebXY1123J，审计表增加登录名后复测）

复查第11周实现时发现，审计表的操作人员取自会话上下文 `tokenhub.actor`，而会话上下文可由任意连接自行设置。为此在 `w11.InventoryAudit` 增加 `login_name` 列，由触发器写入 `ORIGINAL_LOGIN()`，即实际连接数据库的登录名，不受会话上下文影响；`operator` 列的取值方式不变。测试脚本 A2 同时核对登录名，两份清单增加该列。

数据库 `TokenHubDB_v11_WebXY1123J` 于 2026-11-23 用 `tools/app_prepare.py --with-week10 --with-week11 --with-week12` 从空 v0.1 新建，建库后运行 [test_trigger.sql](../../../sql/week11/test_trigger.sql)，并运行 `tests/test_week11_12_sql.py`（9 项，OK，[日志](unittest_week11_12.log)）。本批未运行全量 unittest；改动后的全量 124 项测试另在 [WebXY1123K](../../week12/WebXY1123K/README.md) 运行并通过。以下内容由[原始输出](test_trigger.log)整理，未改动数值；汇总为 `SUMMARY|13/13|TRANCOUNT=0`。此前 [WebXY1123H](../WebXY1123H/README.md) 的记录保留不变，对应增加登录名之前的版本。

## 用例结果

| 编号 | 类别 | 初始数据 | 操作 | 预期结果 | 实际结果 | 是否符合 |
|---|---|---|---|---|---|---|
| A1 | 单条插入 | 审计表 0 行 | 新建 Other 账号 #18，总额度 500000 | 新增 1 行审计：insert，调整前 NULL，调整后 500000 | 新增 1 行：insert，调整前 NULL，调整后 500000，操作人 sql:LAPTOP-OJSK2J30\xy | 符合 |
| A2 | 单条修改 | 账号 #18 库存 500000 | 以 employee:test-admin 身份调用 w10.usp_AdjustInventory +3000 | 新增 1 行：increase，500000→503000，操作人 employee:test-admin，登录名为实际连接登录名 | 新增 1 行：increase，500000→503000，操作人 employee:test-admin，登录名 LAPTOP-OJSK2J30\xy | 符合 |
| A3 | 多条修改 | 账号 #18 库存 503000，账号 #19 库存 800000 | 一条 UPDATE 把两行库存各减 200 | 新增 2 行 decrease，变化量均为 -200，调整前后分别对应各自账号 | 新增 2 行：#18 decrease 503000→502800（-200）；#19 decrease 800000→799800（-200） | 符合 |
| A4 | 正常操作 | 审计表 5 行 | 两行库存只更新时间、数量不变 | 不新增审计记录 | 新增 0 行 | 符合 |
| A5 | 非法数据 | 账号 #18 库存 502800 | UPDATE 库存为 -1 | 约束拒绝（547），库存不变，审计不新增 | 错误 547，库存 502800，审计新增 0 | 符合 |
| A6 | 触发器拒绝 | 账号 #18 已有审计记录 | UPDATE 审计表的操作人字段 | 拒绝（54409），记录不变 | 错误 54409，被改记录 0 行 | 符合 |
| O1 | 正常操作 | 订单 #112 pending，明细 P×2、Q×1 | 调用订单完成事务（状态改为 paid） | 触发器放行，状态 paid | 状态 paid | 符合 |
| O2 | 触发器拒绝 | 订单 #112 已为 paid | UPDATE 状态再次设为 paid | 拒绝（54401），状态仍为 paid | 错误 54401，状态 paid | 符合 |
| O3 | 非法数据 | 订单 #113 pending，无明细 | UPDATE 状态为 paid | 拒绝（54403），状态仍为 pending | 错误 54403，状态 pending | 符合 |
| O4 | 非法数据 | 订单 #114 pending，P×1，金额 12.00 | UPDATE 金额 +1 元并改为 paid | 拒绝（54405），金额与状态不变 | 错误 54405，状态 pending，金额 12.00 | 符合 |
| O5 | 触发器拒绝 | 订单 #115 上游需求 1999966683，Other 可售上游余量 100802649 | UPDATE 状态为 paid | 拒绝（54406），状态仍为 pending | 错误 54406，状态 pending | 符合 |
| O6 | 多条修改 | 订单 #114（有明细）与 #113（无明细）均为 pending | 一条 UPDATE 同时改为 paid | 整条拒绝（54403），两单都仍为 pending | 错误 54403，状态 pending / pending | 符合 |
| O7 | 多条修改 | 订单 #114、#116 均有明细、金额一致 | 事务内一条 UPDATE 同时改为 paid，随后回滚 | 触发器放行 2 行；回滚后仍为 pending | 更新 2 行；回滚后 pending / pending | 符合 |

## 库存审计记录

本次两个测试账号的全部审计行。`operator` 为 `sql:…` 的是直接 SQL 操作（A1 新建账号、A3 多行修改），`employee:test-admin` 是 A2 在会话上下文中设置的操作人；`login_name` 五行都是实际连接的登录名，A2 虽在会话上下文中写了 employee:test-admin，登录名仍记为真实连接。A4 只改时间、A5 被约束拒绝、A6 修改审计被拒绝，均未留下审计行，与预期一致。

| audit_id | account_id | provider | operation_type | quota_before | quota_after | change_quantity | operated_at | operator | login_name |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 18 | Other | insert | NULL | 500000 | 500000 | 2026-11-23 13:33:18.036 | sql:LAPTOP-OJSK2J30\xy | LAPTOP-OJSK2J30\xy |
| 2 | 19 | Other | insert | NULL | 800000 | 800000 | 2026-11-23 13:33:18.085 | sql:LAPTOP-OJSK2J30\xy | LAPTOP-OJSK2J30\xy |
| 3 | 18 | Other | increase | 500000 | 503000 | 3000 | 2026-11-23 13:33:18.197 | employee:test-admin | LAPTOP-OJSK2J30\xy |
| 4 | 19 | Other | decrease | 800000 | 799800 | -200 | 2026-11-23 13:33:18.290 | sql:LAPTOP-OJSK2J30\xy | LAPTOP-OJSK2J30\xy |
| 5 | 18 | Other | decrease | 503000 | 502800 | -200 | 2026-11-23 13:33:18.290 | sql:LAPTOP-OJSK2J30\xy | LAPTOP-OJSK2J30\xy |

## 测试订单状态

订单 112 经完成事务成为 paid；113（无明细）、114（金额被改动的那次更新被拒绝）、115（上游需求超过可售余量）、116（只在回滚的事务中改过状态）都保持 pending，与预期一致。

| order_id | status | total_amount | total_tokens | paid_at |
|---|---|---|---|---|
| 112 | paid | 32.00 | 499951 | 2026-11-23 13:33:19 |
| 113 | pending | 0.00 | 0 | NULL |
| 114 | pending | 12.00 | 133317 | NULL |
| 115 | pending | 1.00 | 1999966683 | NULL |
| 116 | pending | 8.00 | 233317 | NULL |

## 未覆盖的情况

- 删除库存行：触发器按 `deleted` 处理 delete 类型，但现有外键与规则不允许删除被引用的库存，测试未构造该用例。
- 本轮测试以本机 Windows 登录直接连接执行，未在普通 Windows 受限账户下运行；该项属第10周遗留的部署验收，本轮未处理。

窗口查询的原始结果见 [window_query.log](window_query.log)。本批的三个数据库与备份目录已删除（已核对不存在），本目录与构建日志保留。
