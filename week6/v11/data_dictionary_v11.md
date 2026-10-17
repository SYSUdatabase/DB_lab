# v1.1 数据字典与业务规则增量

作用版本：`TokenHubDB_v11_Full261017D`（独立测试副本）。原 v0.1→v1.0 的 15 张表、18 FK 说明见 [v1.0 数据字典](../data_dictionary_v10.md)；本版新增 2 张表及其 2 条 PK/FK 关系，因此为 **17 张表、20 个可信外键**。ER：[源文件](er_diagram_v11.mmd)、[SVG](er_diagram_v11.svg)、[PNG](er_diagram_v11.png)。

## 继承及新增的业务约束

| 编号 | v1.1 实施方式 |
|---|---|
| I01 | pending 可作为编辑草稿；完成支付前必须有明细并核对订单金额、Token。已支付、已退款和部分退款的历史明细不允许普通管理角色直接修改 |
| I02 | `UQ_OrderDetails_order_product` 保留，同单同商品增加 quantity，使用原首次快照单价 |
| I03 | 下单前用户必须已注册且 active，保留 Orders.user_id 非空 FK |
| I04 | UpstreamAccount 创建时自动配对唯一 Inventory，禁止解绑导致账号无库存 |
| I05 | 使用日期/注册/上游账号生命周期/provider 校验；修改上游、用户、商品的已引用元数据时不能破坏历史调用 |
| I06 | 受控支付、消费、补货维护额度、余额、流水及日/周/月统计；直接修改关键余额/库存/汇总被拒 |
| I07 | RestockTask.created_source 为 manual/system；manual 必须有 created_by，system 必须不填员工 |
| I08 | 原 3000 条可核对消费流水从 manual + 模糊编号调整为明确的 `usage` 引用；新增弱引用有效性检查、引用目标删除保护及交易审计不可变约束 |
| I09 | 合成历史余额负事件在独立副本校正；新增 Token 批次 FIFO 分配和事务级余额检查 |
| I10 | 应用 Roles 与 SQL Server hub_* 角色保持独立；敏感流程只通过授权管理过程操作 |
| RF | 新增订单级退款责任账本；未用 Token 扣回与应退金额一次性入账，外部支付完成才登记结算凭证 |

## 新增表与属性

### OrderTokenLots — 按成交明细建立的 Token 批次

| 字段 | 类型 | 键、约束与含义 |
|---|---|---|
| detail_id | INT | **PK + FK → OrderDetails.detail_id**；每条已支付明细最多一个批次 |
| credited_at | DATETIME2(0) | 该订单 paid_at 的快照时间 |
| issued_tokens | BIGINT | 付款时发放的 Token 数量，与明细 total_tokens 对应 |
| consumed_tokens | BIGINT | 已按 FIFO 分配到本批次的实际调用 Token |
| refunded_tokens | BIGINT | 本批次因退款被收回的未消费 Token |

可信 `CK_Lot_Quantity`：`issued_tokens>0`，`consumed_tokens>=0`，`refunded_tokens>=0`，且两者之和不得超过 issued_tokens。写入权限限定为受控账务过程（和授权 dbo 维护），余额分配按同一用户、provider 及购买时间顺序执行。

### RefundLedger — 每订单一次退款的金额责任与结算凭证

| 字段 | 类型 | 键、约束与含义 |
|---|---|---|
| order_id | INT | **PK + FK → Orders.order_id**；唯一，直接阻止同订单产生两次退款责任 |
| refund_id | INT IDENTITY | 额外 **UNIQUE** 事务编号 |
| requested_at | DATETIME2(0) | 退款申请的数据库时间 |
| refund_amount | DECIMAL(10,2) | 按该订单未消费 Token 比例计算的应退金额，大于零 |
| refundable_tokens | BIGINT | 本次已收回的 Token |
| consumed_tokens | BIGINT | 订单原发放 Token 中已实际使用的数量（不予退还） |
| payout_state | VARCHAR(24) | `awaiting_transfer` 或 `settled` |
| external_payout_ref | VARCHAR(120) | UNIQUE；外部支付成功凭证编号，待支付时必须 NULL |
| settled_at | DATETIME2(0) | 收到外部退款成功凭证的登记时间，待支付时必须 NULL |

校验：`CK_Refund_positive`、`CK_Refund_state` 与 UNIQUE；既有 Orders.status 增加 `partially_refunded`，支付时间的可信 CHECK 同步适配。

**退款边界**：数据库记录 `refund_amount` 为**应退金额**，不会自动向银行卡或第三方支付平台转账。收到真实支付凭证后由授权员工调用 `usp_W6_AttestRefundPayout` 标记 settled；SQL Server 不自行验证支付平台回调。曾被标记为 refunded 的旧合成订单没有网关凭证，不新建虚假的结算流水。

## 事务入口

| 存储过程 | 业务处理 |
|---|---|
| `usp_W5_CreateRegisteredOrder`、`usp_W5_AddMergedOrderItem` | 有效注册用户创建 pending 订单，同商品数量合并 |
| `usp_W6_PayPendingOrder` | 订单支付、TokenBalances 入账、OrderTokenLots 发放同事务 |
| `usp_W5_RecordUsage` | 余额扣减、上游配额/库存、InventoryLog usage 关联、UsageSummary、FIFO 批次消耗同事务 |
| `usp_W6_RestockAccount` | RestockTask、上游配额、Inventory 和流水同事务 |
| `usp_W6_RequestRefund` | 逐明细回收未消费 Token，并记录按原价计算的应退金额，按已消费情况标记 refunded / partially_refunded；重复调用返回原记录 |
| `usp_W6_AttestRefundPayout` | 登记外部支付成功凭证并改为 settled，同凭证重复登记幂等，不同凭证拒绝 |

完整迁移脚本、控制约束及正反例详见 [统一 v1.1 入口](README.md)。本机新副本对旧合成时间线的四项异常校正后计数均为零；旧 v0.1 和队友 sh 上原 v1.1 并未被更改。

