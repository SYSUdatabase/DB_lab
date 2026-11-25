# 第13周：双会话并发验证

从项目根目录按[第三阶段复现](../../README.md#第三阶段从空库复现)构建新的 `WebW13...` 批次。不要连接已在使用的业务库。下列现象实验使用专用 schema `w13lab`；其中 P、Q 为按商品计件的简化库存，分别为 10、8。实际业务仍以供应商的上游额度计量，订单支付发放 Token 并占用可售余量，顾客调用才扣物理库存。

## 自动核验

```powershell
.\.venv\Scripts\python.exe tools/week13_verify.py --server $ServerInstance --suffix $Suffix
```

工具在 A、B 两个连接执行下列同一批 SQL 段，用观察连接读取锁和等待信息。观察账号需有 SQL Server 实例 DMV 查看权限。工具不更改 RCSI 或其他实例设置。证据写入 `result/week13/<RunId>/concurrency.jsonl`，拒绝覆盖旧结果；实际竞购会留下专用测试订单，每次完整重放请用新批次。

专项回归额外检查供应商别名、手工脚本等锁超时后的回滚，以及 Web 请求在 SQL 等锁超时时返回 409。可在并发重放前运行：

```powershell
$env:DB_LAB_WEEK13_DATABASE = "TokenHubDB_v11_$Suffix"
$env:DB_LAB_TEST_SERVER = $ServerInstance
.\.venv\Scripts\python.exe -m unittest discover -s tests -p test_week13_sql.py -v
```

## 手工重放

1. 在 SSMS 打开三个查询窗口，数据库下拉框都选本轮 `TokenHubDB_v11_<RunId>`。在观察窗口单独执行 [init.sql](init.sql)。
2. 在 A、B 各执行 [session.sql](session.sql)，记录 SPID、数据库名、SQL Server 版本、初始隔离级别和 RCSI，确认 SPID 不同。
3. 打开下表相应的 A/B 脚本，只选中一个 `-- step:` 代码块执行。每出现阻塞，保持等待窗口运行，在观察窗口执行 [observe.sql](observe.sql)；记录等待者、阻塞者、等待类型、键资源描述、所属表、锁模式和授予/等待状态。然后回到可执行的另一窗口操作。
4. 每轮结束在观察窗口执行 [state.sql](state.sql)。确认 A、B 均为 `@@TRANCOUNT=0` 后，在观察窗口运行 [reset.sql](reset.sql)，再做下一轮。同一行表中用分号分开的两轮也须重置。

遇到超时或其他错误时停止本轮。写入段会回滚能捕获的 SQL 错误；若在 SSMS 手动取消查询，仍须在两边检查 `@@TRANCOUNT` 并显式回滚未结束的事务，再重置库存。

| 场景 | A/B 脚本和顺序 | 预期 |
|---|---|---|
| 同行写等待 | [A](write_wait_A.sql) / [B](write_wait_B.sql)。A1 → B1 等待 → A2_commit；重置后 A1 → B1 等待 → A2_rollback | 提交轮 P=13、订单 paid；回滚轮 P=15、订单 pending；两轮补货均 completed、实际 +5 |
| 脏读和已提交读 | [A](dirty_read_A.sql) / [B](dirty_read_B.sql)。A1 → B1_ru → A2；重置后 A1 → B1_rc → A2；再重置执行 B1_locking_rc 对照 | RU 先见 15，A 回滚恢复 10。RCSI 关时 RC 等到回滚才读 10；RCSI 开时 RC 直接读先前提交的 10。锁提示对照会等待 |
| 不可重复读与可重复读 | [A](repeatable_read_A.sql) / [B](repeatable_read_B.sql)。A1_rc → B1 提交 → A2；重置后 A1_rr → B1 等待 → A2 提交 | RC 两次读 10、15；RR 两次均为 10，随后 B 完成，P=15 |
| 反序死锁 | [A](deadlock_A.sql) / [B](deadlock_B.sql)。A1 锁 P → B1_reverse 锁 Q → A2 等 Q → 观察 → B2_reverse 请求 P | B 设置较低死锁优先级，返回 1205；B 对 Q 的增加被撤销，A 提交后 P=8、Q=6，补货未完成 |
| 同序改进 | 同一组脚本。A1 锁 P → B1_ordered 请求 P 并等待 → 观察 → A2 更新 Q 后提交 | 两边均按主键 1→2 更新；B 先在 P 排队，不持有 Q。两边完成，P=13、Q=11 |

## 实际订单竞争

在同一实验库执行 [business_fixture.sql](business_fixture.sql) 一次，记录两笔订单编号。脚本按现有 Other 可售余量动态计算每份的上游额度，并新增少量同供应商额度，使可售余量恰为 10 份；不更改原商品或历史数据。每单购买 P×6。`business_gate_check.sql` 在回滚边界内分别检查订单和补货持有同名事务锁。

1. A 运行 `BEGIN TRAN; EXEC w12.usp_CompleteOrder <order_a>;`，先不提交。
2. B 运行 `EXEC w12.usp_CompleteOrder <order_b>;`。观察 DMV；若等待发生在其他先取得的数据库锁上，也要按实际资源记录。
3. A 运行 `COMMIT;`；B 应返回 53132。确认只有 A 的订单为 paid 且仅有 A 的余额和批次发放，B 仍 pending、无完成时间、无批次。用 `w11.fn_ProviderSellable('Other')` 核对 `(available_quota-outstanding_upstream)/units_per_pack = 4`；物理库存不因支付减少。

实验后在 A、B 各运行：

```sql
IF @@TRANCOUNT>0 ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET DEADLOCK_PRIORITY NORMAL;
SET LOCK_TIMEOUT -1;
SELECT @@TRANCOUNT AS trancount;
```

[cleanup.sql](cleanup.sql) 只删除简化实验表和索引实际订单的夹具表，不删除实际业务测试订单及其历史；完整清理请关闭所有本轮连接，再按[根 README 的 RunId 清理](../../README.md#每次复现后的清理按-runid)删除专用本轮库及备份。

新建库时第三阶段锁随第12周事务一并安装；[upgrade.sql](upgrade.sql) 只供已经用旧代码构建的 `WebW13...` 专用库重放，使用 `sqlcmd -v "DatabaseName=$env:DB_LAB_APP_DATABASE"` 明确库名。不运行该脚本也不影响旧库保留历史。
