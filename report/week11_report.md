# 第11周触发器与窗口函数报告

## 实现范围

第11周增量装在第10周扩展之后，安装入口为 `sql/week11/install.sql`，`tools/app_prepare.py --with-week10 --with-week11` 从空库复现。增量为1张审计表、1个可售余量函数、3个触发器和1个审计对应商品视图，不改动已有业务数据，安装前后8张核心表的计数与校验和一致（由准备脚本比对）。

| 对象 | 类型与用途 |
|---|---|
| dbo.trg_W11_InventoryAudit | `dbo.Inventory` 的 AFTER INSERT/UPDATE/DELETE 触发器，逐行写入库存审计 |
| w11.InventoryAudit | 审计表：库存对象编号、账号、供应商、操作类型、调整前后数量、变化量、操作时间、操作人员、连接登录名 |
| w11.trg_InventoryAuditImmutable | 审计记录只允许追加，修改或删除报 54409 |
| dbo.trg_W11_OrderCompletionRules | `dbo.Orders` 的 AFTER INSERT/UPDATE 触发器，订单改为已完成（paid）时核对规则 |
| w11.fn_ProviderSellable | 内联表值函数，返回某供应商的可用上游库存与已售未消费部分的上游消耗 |
| w11.v_InventoryAuditProduct | 视图：把每条审计按供应商展开到受影响的商品编号，不改动审计表 |
| sql/week11/window_query.sql | 排名、累计值、移动平均三条查询 |

## 库存审计触发器

本项目的库存按上游账号保存（`Inventory.account_id` 与 `UpstreamAccount` 一一对应），商品按 `model_provider` 对应同一供应商的账号，因此审计记录库存行编号、账号编号和供应商，不单独记录商品编号。需要按商品查看时，视图 `w11.v_InventoryAuditProduct` 按“账号→供应商→该供应商的套餐”把每条审计展开为受影响的商品编号，一条审计对应该供应商的每个商品各一行，审计表本身不变。操作类型分为 insert、increase、decrease、delete，变化量等于调整后减调整前，由 CHECK 约束保证。

触发器用 `inserted` 与 `deleted` 按 `inventory_id` 全外连接，一条语句改多行时逐行记录；只改 `last_updated_at`、数量不变的行不记录。操作人员取会话上下文 `tokenhub.actor`：Web 入口 `app.[Execute]` 与 `app.Week10` 在解析会话后写入 `employee:编号` 或 `user:编号`，每次调用都覆盖；直接用 SQL 连接操作时记为 `sql:登录名`。会话上下文可由任意连接自行设置，不能单独作为可信身份，因此审计表另有 `login_name` 列，由触发器写入 `ORIGINAL_LOGIN()`，即实际连接数据库的登录名，不受会话上下文影响。审计表与业务修改在同一事务中，业务回滚时审计一并回滚，因此它记录的是已生效的库存变化，不作为失败日志。

## 订单完成规则触发器

项目组确定数据库状态值仍为 `paid`，报告与测试记录统一写作“已完成（paid）”，不另设“已完成”状态，以免与“已支付”重复。订单状态改为已完成（paid）时，触发器把本次涉及的订单放进表变量，按集合依次检查，任一订单不满足即拒绝整条语句：

| 检查 | 错误号 |
|---|---|
| 原状态已是已完成（paid）、refunded 或 partially_refunded，属于重复完成 | 54401 |
| 原状态不是 pending（如 cancelled） | 54402 |
| 没有订单明细 | 54403 |
| 明细引用的商品不存在，或数量、Token 不为正 | 54404 |
| 订单金额、Token 与明细合计不一致 | 54405 |
| 按供应商汇总的上游需求超过可售余量 | 54406 |

可售余量以上游库存为单位：有效且未过期账号的当前库存之和，减去已售出但顾客尚未消费、也未退款的部分将要消耗的上游库存。订单需求按“份数 × 每份上游消耗（`required_upstream_tokens`）”计算，已售未消费部分按批次剩余 Token 折算成份数后再乘每份上游消耗。项目组决定保持原有扣减时机：上游库存仍在顾客模拟调用时按实际用量扣减，订单完成时只把 Token 记入顾客余额，所以完成时核对可售余量，避免售出的 Token 超过上游能提供的数量。原有的 `trg_W5_OrdersFinalized` 也核对明细与金额，本触发器通过 `sp_settriggerorder` 设为先执行，拒绝时给出本周的错误号。本触发器只处理插入和修改，不处理删除：已完成（paid）的订单都有明细，`FK_OrderDetails_Orders` 外键使其不能被直接删除；被库存流水或异常记录引用的订单由原有触发器 `trg_W5_BlockDeleteReferencedOrders` 拒绝删除（51983）；Web 入口只允许管理员删除没有明细的 pending 或 cancelled 订单。因此删除操作不会绕过完成规则。

## 窗口查询

三条查询沿用第10周的成交口径：状态为 paid、refunded、partially_refunded 的订单，金额取明细折后小计，日期取 `paid_at`。因此下文的“销售金额”是成交额：之后发生退款的订单仍按原成交金额计入，不是扣除退款后的净收入。下列结果来自 WebXY1123H 新库的样例数据，统计区间 2026-07-01 至 2026-09-30，原始输出见 [window_query.log](../result/week11/WebXY1123H/window_query.log)。

**排名。** 按销售金额对商品排名，同时给出 RANK、DENSE_RANK、ROW_NUMBER，并在供应商内按销量排名。金额最高的是 Claude 1M Token包（1018.30 元）。OpenAI 100K 与 Claude 100K 同为 131.10 元：RANK 均为 6，下一名为 8；DENSE_RANK 均为 6，下一名为 7；ROW_NUMBER 按商品编号给出 6 和 7。前者适合“前 N 名”的名次，后者适合需要连续名次的榜单。供应商内销量排名可用于选择各供应商主推的套餐。

**累计值。** 按成交日期升序累计，窗口为 `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`，排序字段为 `sale_date`。区间第一天 2026-07-01 为 133.60 元，最后一个成交日 2026-09-21 累计 4294.60 元、194 件，可用于观察季度内的销售进度。

**移动平均。** 计算当天及前两天共 3 个自然日的平均销售金额和销量。没有成交的日期先用日历补 0，`ROWS BETWEEN 2 PRECEDING AND CURRENT ROW` 才等于最近 3 天；区间前两天不足 3 天，`window_days` 列出实际天数。例如 2026-07-03 的 3 日均额为 (133.60+0+160.00)/3=97.87 元。该指标平滑单日波动，可作为补货节奏的参考。

## 验证

| 检查 | 结果与证据 |
|---|---|
| 新库构建 | WebXY1123H 从 v0.1 构建至第12周，准备退出码 0，安装日志位于 `result/webapp/WebXY1123H/` |
| 失败批次 | 第一次验收批次 WebXY1123F 的全量测试有 11 项未通过，原因与修正见[失败批次说明](../result/week12/WebXY1123F/README.md) |
| 触发器测试 | 13 项全部符合，`@@TRANCOUNT=0`，[验证记录](../result/week11/WebXY1123H/README.md) |
| 增加登录名后复测 | WebXY1123J 从空库构建至第12周，触发器 13 项全部符合，`tests/test_week11_12_sql.py` 9 项通过，[验证记录](../result/week11/WebXY1123J/README.md) |
| 增加登录名后全量测试 | WebXY1123K 从空库构建至第12周，全量 unittest 124 项通过、0 跳过，[测试记录](../result/week12/WebXY1123K/README.md) |
| 对齐讲义后复测 | WebXY1123S 从空库构建至第12周，触发器 14 项全部符合（新增 A7：审计对应商品视图），全量 unittest 124 项通过，[验证记录](../result/week11/WebXY1123S/README.md) |
| 最新复测 | WebXY1124B 从空库构建至第12周，触发器 14 项全部符合，`@@TRANCOUNT=0`，窗口查询退出码 0，[验证记录](../result/week12/WebXY1124B/README.md) |
| 窗口查询 | 三条查询退出码 0，[原始输出](../result/week11/WebXY1123H/window_query.log) |
| 自动化测试 | `tests/test_week11_12_sql.py` 随全量 unittest 运行，结果见[第12周报告](week12_report.md) |

测试覆盖单条插入（新建账号自动生成库存）、单条修改（经第10周库存调整过程）、一条语句修改两行、数量不变的修改、负库存被约束拒绝、审计记录被修改时拒绝，订单的正常完成、重复完成、无明细、金额不符、可售余量不足、一条语句中合格与不合格订单混合、两张合格订单同时完成，以及审计记录经视图 `w11.v_InventoryAuditProduct` 对应到商品编号（A7）。

## 已知限制

- **直接 SQL 并发完成订单时可能超卖。** 订单完成规则触发器读取可售余量时不加锁，两个连接同时直接 UPDATE 同一供应商的不同订单，可能都读到足够的余量而同时通过。经 Web 支付时走第12周的 `w12.usp_CompleteOrder`，该过程在 SERIALIZABLE 隔离级别下先以 UPDLOCK、HOLDLOCK 锁定订单与余额再核对余量，不受影响。直接 SQL 路径的并发控制留待第13周并发实验处理。
- **网页上的错误提示较笼统。** 本周新增的错误号 54401—54409 位于 50000—55999 区间，`webapp/errors.py` 将该区间统一映射为业务规则错误（HTTP 409），页面显示通用提示，不区分是重复完成、金额不符还是余量不足。具体原因记录在数据库错误号与服务端日志中。为不改动网站代码，本周未细分提示。
- **测试未覆盖的情况。** 删除库存行由触发器按 delete 类型处理，但现有外键与规则不允许删除被引用的库存，测试未构造该用例；触发器测试以本机登录直接连接运行；受限账户下的实际写入已于 2026-11-23 另行核对（订单完成、调用扣减、补货入库、库存校正均正常，审计 login_name 为运行账户），见[补做记录](../result/week12/WebXY1123R/README.md)。
