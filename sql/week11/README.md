# 第11周 SQL

在已安装第10周扩展的 v1.1 Web 专用库上运行增量安装。`install.sql` 校验库名、第10周前置对象与重复安装，审计表、函数和触发器在一个事务内提交。

```powershell
sqlcmd -S 'localhost\SQLEXPRESS' -E -C -b -f 65001 -d $env:DB_LAB_APP_DATABASE -v "DatabaseName=$env:DB_LAB_APP_DATABASE" -i sql/week11/install.sql
sqlcmd -S 'localhost\SQLEXPRESS' -E -C -b -f 65001 -d $env:DB_LAB_APP_DATABASE -v "DatabaseName=$env:DB_LAB_APP_DATABASE" -i sql/week11/test_trigger.sql
sqlcmd -S 'localhost\SQLEXPRESS' -E -C -b -f 65001 -d $env:DB_LAB_APP_DATABASE -W -i sql/week11/window_query.sql
```

新库可直接用 `tools/app_prepare.py --suffix <新后缀> --with-week10 --with-week11` 构建。

| 文件 | 内容 |
|---|---|
| `trigger.sql` | 审计表 `w11.InventoryAudit`、库存审计触发器 `dbo.trg_W11_InventoryAudit`、可售余量函数 `w11.fn_ProviderSellable`、订单完成规则触发器 `dbo.trg_W11_OrderCompletionRules` |
| `window_query.sql` | 商品销售排名、按日累计销售额、最近 3 天移动平均，只读 |
| `test_trigger.sql` | 13 个用例，按“编号\|类别\|初始数据\|操作\|预期结果\|实际结果\|是否符合”输出，任一不符合则以 57900 结束 |
| `install.sql` | 增量安装入口 |

库存审计的操作人员来自会话上下文 `tokenhub.actor`。`app.[Execute]` 与 `app.Week10` 在解析会话后写入 `employee:编号` 或 `user:编号`；直接 SQL 连接时记为 `sql:登录名`。会话上下文可由连接自行设置，因此审计表另有 `login_name` 列，由触发器写入 `ORIGINAL_LOGIN()`，记录实际连接数据库的登录名。

| 错误号 | 含义 |
|---|---|
| 54401 | 订单已完成，不能再次完成 |
| 54402 | 只有 pending 订单可以完成 |
| 54403 | 订单没有明细 |
| 54404 | 明细商品不存在或数量、Token 不为正 |
| 54405 | 订单金额或 Token 与明细合计不一致 |
| 54406 | 上游需求超过可售余量 |
| 54409 | 审计记录只允许追加 |
