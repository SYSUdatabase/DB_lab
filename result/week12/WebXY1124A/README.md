# 第12周并发死锁修正与复测（WebXY1124A）

复查第12周时发现：不同顾客同时完成同一供应商的订单会大量死锁。`sql/week12/order_transaction.sql` 在核对可售余量之前增加一条语句，以 `UPDLOCK,HOLDLOCK` 锁住本单涉及供应商的 `dbo.UpstreamAccount` 行，使同一供应商的订单完成排队。2026-11-23 用新后缀 WebXY1124A 从空库构建至第12周复测。

| 步骤 | 命令与结果 |
|---|---|
| 建库 | `tools/app_prepare.py --suffix WebXY1124A --with-week10 --with-week11 --with-week12`，退出码 0，第10—12周安装均 PASS |
| 事务测试 | `sql/week12/test_transactions.sql`：12/12 符合，`TRANCOUNT=0`（[日志](test_transactions.log)）；递归查询 [日志](recursive_query.log) |
| 第11—12周测试 | `python -m unittest tests.test_week11_12_sql -v`：9 项 OK（[日志](week11_12_unittest.log)） |
| 全量测试 | `DB_LAB_TEST_DATABASE` 指向 `TokenHubDB_v01_WebXY1124A`，`DB_LAB_APP_DATABASE`、`DB_LAB_WEEK10_DATABASE`、`DB_LAB_WEEK12_DATABASE` 指向 `TokenHubDB_v11_WebXY1124A`，`DB_LAB_PREVIEW=1`；`python -m unittest discover -s tests -v` 共 124 项 OK，0 跳过（[日志](full_unittest.log)） |
| 代码检查 | `ruff check webapp tests tools`、`ruff format --check webapp tests tools` 均通过（[日志](ruff.log)）。对整个仓库运行 ruff 时 `db_tools/` 下旧脚本有 20 项原有问题，不在规定检查范围内，未改动 |

以上测试都在修改后的过程上运行，在压测之前完成。

## 并发压测

脚本 [stress.py](stress.py)：新建 6 个顾客和一个 Other 商品，每个顾客 20 张待完成订单；6 个线程同时完成，先直接调用 `w12.usp_CompleteOrder`（120 单），再经 `app.[Execute]` 的 `orders.pay` 以受限身份 `app_runtime_probe` 调用（另 120 单）。修改前的过程由 [alter.py](alter.py) 按仓库文件去掉新增的锁语句后临时替换，测完恢复为已提交版本。

| 过程版本 | 直接 SQL（120 单） | 经 Web 入口（120 单） | 一致性 |
|---|---|---|---|
| 修改前 | 成功 36，死锁（1205）84，用时 18.5 秒 | 成功 37，死锁 83，用时 13.2 秒 | 库存、余额与批次均无不一致 |
| 修改后 | 120 全部成功，用时 1.3 秒 | 120 全部成功，用时 1.7 秒 | 同上 |

原始输出见 [stress.log](stress.log)。第一次压测时，修改后一轮为 120/120、120/120；修改前一轮因测试商品的（供应商，Token 数）与前一轮重复触发唯一约束，没有执行；恢复步骤的脚本也有误。修正后整组重跑，日志为重跑结果。复查期间在临时库 WebXY1123V（391d95e，已删除）上的同类测量为：直接 SQL 死锁 78/120 与 89/120，经 Web 82/120。

死锁的原因：可售余量函数以 SERIALIZABLE 读取该供应商的全部已售批次，两个事务各自持有这段范围的共享锁，随后都要插入新批次，互相等待。加锁后，第二个事务在读取前就等待第一个提交，不再出现交叉等待。

## 清理

`tools/cleanup_reproduction.ps1 -Suffix WebXY1124A -KeepEvidence` 删除三个数据库与备份，本目录与构建日志保留。
