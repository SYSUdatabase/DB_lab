# 第12周 SQL

在已安装第11周扩展的库上运行增量安装。`install.sql` 校验库名、第11周前置对象与重复安装，分类层级、递归函数和两项事务在一个事务内提交。原支付过程 `dbo.usp_W6_PayPendingOrder` 与原补货完成过程 `dbo.usp_W6_RestockAccount` 改为调用本周事务，Web 入口不变。

```powershell
sqlcmd -S 'localhost\SQLEXPRESS' -E -C -b -f 65001 -d $env:DB_LAB_APP_DATABASE -v "DatabaseName=$env:DB_LAB_APP_DATABASE" -i sql/week12/install.sql
sqlcmd -S 'localhost\SQLEXPRESS' -E -C -b -f 65001 -d $env:DB_LAB_APP_DATABASE -W -i sql/week12/recursive_query.sql
sqlcmd -S 'localhost\SQLEXPRESS' -E -C -b -f 65001 -d $env:DB_LAB_APP_DATABASE -v "DatabaseName=$env:DB_LAB_APP_DATABASE" -i sql/week12/test_transactions.sql
```

新库可直接用 `tools/app_prepare.py --suffix <新后缀> --with-week10 --with-week11 --with-week12` 构建。

| 文件 | 内容 |
|---|---|
| `category.sql` | 分类表 `w12.ProductCategories`、商品分类表、防环触发器、递归函数 `w12.fn_CategoryDescendants` 与样例层级 |
| `recursive_query.sql` | 层级结构说明、样例数据，以及根节点、中间节点、叶子节点、不存在编号四次递归查询，只读 |
| `order_transaction.sql` | 订单完成事务 `w12.usp_CompleteOrder(@order_id)`，原支付过程改为调用它 |
| `restock_transaction.sql` | 补货入库事务 `w12.usp_ReceiveRestock(@task_id, @actual_amount)`，原补货完成过程改为调用它 |
| `test_transactions.sql` | 12 个用例：两项事务各自的正常提交、中途失败回滚、重复调用、规则拒绝、原入口调用，以及账务一致性检查 |
| `install.sql` | 增量安装入口 |

调用顺序：准备补货单或待支付订单 → 调用事务过程（或经 Web 的“完成补货”“模拟支付”）→ 查询订单、余额、批次、库存、流水、审计和单据核对结果。测试连接可设置会话上下文 `w12.fail_point` 为 `order_after_credit` 或 `restock_after_inventory`，在部分数据已写入后主动抛错，验证回滚。

| 错误号 | 含义 |
|---|---|
| 53123 | 订单不存在或不是待支付状态 |
| 53125 | 订单没有明细 |
| 53131 | 订单已完成，不再记入余额 |
| 53132 | 上游需求超过可售余量 |
| 53303 | 入库数量不为正 |
| 53310 | 补货单不存在 |
| 53311 | 补货单已入库，不再增加库存 |
| 53312 | 补货单已关闭 |
| 53313 | 账号所属供应商没有在售商品 |
| 54420 | 分类层级会成环或超过 32 层 |
| 54490、54491 | 测试故障点触发的回滚 |

其余错误号沿用原支付与补货过程。
