# 第10周 SQL

在完整 v1.1 Web 专用库上运行增量安装。`install.sql` 校验 `DatabaseName`、Web 库名、前置对象与重复安装，所有结构、回填、过程适配和授权在一个事务内提交。

```powershell
sqlcmd -S 'localhost\SQLEXPRESS' -E -C -b -f 65001 -d $env:DB_LAB_APP_DATABASE -v "DatabaseName=$env:DB_LAB_APP_DATABASE" -i sql/week10/install.sql
sqlcmd -S 'localhost\SQLEXPRESS' -E -C -b -f 65001 -d $env:DB_LAB_APP_DATABASE -v "DatabaseName=$env:DB_LAB_APP_DATABASE" -i sql/week10/regression.sql
sqlcmd -S 'localhost\SQLEXPRESS' -E -C -b -f 65001 -d $env:DB_LAB_APP_DATABASE -v "DatabaseName=$env:DB_LAB_APP_DATABASE" -i sql/week10/call_examples.sql
```

## 对象与口径

| 对象 | 参数与结果 |
| --- | --- |
| `w10.fn_OrderDiscount` | 输入 `DECIMAL(18,2)` 原价，返回一行 `discount_rate,discount_amount`。达到100元为5%，达到500元为10%，负值和NULL返回空表。 |
| `w10.fn_ReplenishmentQuantity` | 输入商品、账号、最低量、目标量，返回BIGINT建议量。最低量NULL使用账号安全阈值，当前量低于最低量时补至目标。缺失/不匹配/无效账号、非法阈值或库存不一致返回NULL。 |
| `w10.fn_SalesSummary` | 输入开始、结束DATE，按商品返回 `product_id,name,sales_quantity,sales_amount,order_count`，NULL或倒置返回空表。 |
| `w10.usp_SalesStatistics` | 相同日期输入，拒绝NULL与倒置。默认返回总览及商品明细两组结果。`@emit_result=0,@app_data OUTPUT` 返回同次物化数据生成的JSON。 |
| `w10.usp_AdjustInventory` | 输入商品、账号、BIGINT有符号调整量、NVARCHAR(MAX)原因、管理员、UUID操作键。默认返回调整表一行。`@emit_result=0,@app_result_id BIGINT OUTPUT` 静默返回编号。 |
| `w10.usp_RepriceDraft` | 内部过程，锁定待支付订单后按订单规则统一重算逐行金额与订单总额。 |

销售以 `paid_at` 的Asia/Shanghai日期为准，包含首尾两天，9999-12-31使用安全上界处理。状态包括 `paid`、`refunded`、`partially_refunded`。销量为套餐件数，成交额包含后续退款订单原成交额。订单数按订单去重，金额聚合为DECIMAL(38,2)，数量与订单数为BIGINT。

旧订单和明细回填为 `legacy`，原金额、Token与批次保持原值。迁移事务内临时禁用历史明细保护，完成回填后恢复，任意安装失败由同一事务回滚。保护范围包含部分退款订单。

新订单使用 `amount-v1`。逐行保存原价、折扣率、优惠额和折后小计。每行优惠四舍五入至分，订单金额取逐行小计之和。订单规则保存在Orders，空草稿也具有明确版本。合并商品保留首次单价与Token快照，增改删后重算。支付核验快照与规则后沿用批次发放，退款按保存的折后小计执行。

库存调整限当前有效管理员。商品与账号供应商必须一致，账号有效且库存账务一致。用DECIMAL(20,0)中间值校验BIGINT范围后，同时修改账号总额度与库存，写入manual调整流水与不可修改的调整记录。保持历史used_quota。同键同参返回原记录，同键异参冲突。事务操作键应用锁先于商品、账号、库存行锁，账号先于库存，失败整体回滚。

## 受控入口

`app.Week10(@token_hash VARBINARY(32), @operation VARCHAR(50), @payload NVARCHAR(MAX))` 根据有效会话解析员工身份，固定返回一行 `data` JSON。`app_runtime`仅获得这个新增入口的EXECUTE权限。

| operation | JSON输入 | JSON结果 |
| --- | --- | --- |
| `reports.sales` | `start_date,end_date`，ISO日期 | `summary`及`items` |
| `restocks.recommendation` | `product_id,account_id,minimum_quota,target_quota` | `recommended_quantity` |
| `inventory.adjustments.create` | `product_id,account_id,change_amount,reason,operation_key` | 调整表记录 |
| `inventory.adjustments.list` | 可选`product_id,account_id,page,page_size` | `items,total,page,page_size` |

前两项限店员或管理员，后两项限管理员。入口拒绝未知字段、重复字段与不匹配的JSON类型，员工来自会话。调整记录字段为 `adjustment_id,operation_key,product_id,account_id,operator_id,change_amount,reason,before_current_quota,after_current_quota,before_total_quota,after_total_quota,log_id,created_at`。原因长度按UTF-16字节检查，最多255个NVARCHAR单元，保留传入内容用于重放比对。

错误号56000表示参数无效，56001表示未认证，56003表示无权限，56004表示对象不存在，56009表示冲突或账务状态异常。现有交易过程原有错误号保留。

`regression.sql`覆盖函数阈值/NULL、空结果和最大日期、可信约束、商品销售分组、折扣支付及退款保留成交额、库存正负校正及同键重放、预期错误。写入夹具在事务结束时回滚。扩展并发、故障注入与HTTP验收见 `tests/test_week10_sql.py` 和 `tests/test_week10_web.py`。
