# 第六周 v1.1 统一数据库版本

本目录合并了第五周遗留问题的 v1.1 业务修复、历史合成数据校正、受控支付/消费/补货、Token 批次追溯和退款申请账本。结构为 **17 张物理表、20 个可信外键**。统一 ER：[Mermaid](er_diagram_v11.mmd) / [SVG](er_diagram_v11.svg) / [PNG](er_diagram_v11.png)；字段与规则见 [数据字典](data_dictionary_v11.md)。

## 已完成测试的目标库

在 `xiao_ruan` 本地 SQL Server 使用全新名称 `TokenHubDB_v11_Full261017D`，从未修改的 `TokenHubDB_v01_A` 独立备份、校验、还原，依次运行 v1.0 迁移、v1.1 业务规则、合成历史修复及退款模块。**源 v0.1、既有 v1.0，以及队友 sh 电脑原有的 v1.1 均未修改。** 第六周第二阶段报告也未修改。

旧样例异常（订单早于注册、调用早于注册、上游账号有效区间/provider 不符、历史负余额）：修复前 `20 / 402 / 225 / 1`，新副本中修复后 `0 / 0 / 0 / 0`。仅对通过 `tools/datagen.py` 固定种子身份和业务指纹匹配的合成样例校正，保留原值备份与逐行 [修改审计](../../result/week6/v11/Full261017D/synthetic_repair_audit.json)，不用于未知来源的交易数据。

## 退款业务规则

- 原已支付订单生成的 Token 按付款时间、明细编号建批次；调用按 **FIFO** 扣减每笔订单的 Token 批次。旧有已退款的两笔样例不重新发放 Token，也不伪造支付凭证。
- `usp_W6_RequestRefund @order_id` 对该笔订单未消费且未退款的 Token 执行**一次性全额可退余额回收**，退还的金额按对应订单明细的实际成交小计乘以「可退 Token / 原发放 Token」计算，逐明细四舍五入到分。**已消费部分不退 Token、也不退对应金额**；不可退或低于一分时拒绝新退款。
- 未消费订单变为 `refunded`；已消费部分 Token 的订单变为 `partially_refunded`，消费记录保留。退款过程中同事务更新 Token 余额、批次已退款数量、订单状态与退款流水。每个订单的 `RefundLedger.order_id` 唯一；重复提交返回原退款记录，不重复扣币或产生第二次应付款。
- **现金不会由 SQL Server 自动转账。** `RefundLedger.refund_amount` 是已确认的**应退金额**，`payout_state='awaiting_transfer'` 表示尚待原支付渠道处理。只有外部支付系统完成实际转账并取得凭证后，才能由授权员工调用 `usp_W6_AttestRefundPayout` 登记凭证并转为 `settled`。SQL 不直接核验支付网关真实性，操作端必须人工/服务端核对凭证；不能把本地 PASS 当成客户已到账。
- 默认不支持同订单分多笔退款、不支持退还已消费部分的现金，也不支持跨订单挪用 Token 来冒充该订单未消耗额。这些规则与明细级 FIFO 都记录在数据库中。若之后要实行按已消费额度扣违约金、部分服务退费等政策，需要业务审批并另做实现。

**新增表**：`OrderTokenLots(detail_id PK/FK, credited_at, issued_tokens, consumed_tokens, refunded_tokens)`，`RefundLedger(order_id PK/FK, refund_id UK, requested_at, refund_amount, refundable_tokens, consumed_tokens, payout_state, external_payout_ref, settled_at)`。两条新增联系均为标识性 PK/FK；v1.0/v1.1 旧有的 18 条 FK 不变。

## 完整复现命令

从项目根目录执行，**每次使用未用过的新后缀**：

```powershell
python -B .\week6\v11\run_full.py --suffix NewV11Run01
```

入口按顺序进行：

1. [build_sandbox.py](build_sandbox.py)：备份（COPY_ONLY/CHECKSUM）、RESTORE VERIFYONLY、还原到新的 v1.0/v1.1，应用既有五周问题修复和原始回归。
2. [repair_generated_history.py](repair_generated_history.py)：只针对验证过的合成样例再备份，原子更正时间/账号/库存流水，并保留逐条 JSON 审计。
3. [deploy_extension.py](deploy_extension.py)：原有消费/库存/元数据保护、受控支付及补货。
4. [install_refund.py](install_refund.py)：[退款表结构](../../sql/v11/07_refund_schema.sql) → [历史 Token 批次分配](seed_token_lots.py) → [批次化支付和调用](../../sql/v11/08_accounting_lots.sql) → [退款与凭证流程](../../sql/v11/09_refund_workflow.sql)。
5. [validate_hardened.py](validate_hardened.py) 与 [qa_approved_rules.py](qa_approved_rules.py)：完整回归、图/结构检查。

**全部测试通过：**原 v1.0 R01–R12、基础 v1.1 测试、VFY01–VFY14、加固 X01–X10、补货 Y01–Y04、退款 RF01–RF06，以及 17 表/20 FK ER 检查。日志见 [本轮一键复现记录](../../result/week6/v11/Full261017D/)；正反例在事务中回滚，退款样例不会形成对外支付。

## 文件维护与版本边界

原 `issue_fixes` 和 `hardening` 的基础脚本统一保存在这里，按步骤执行，不能跳过前置脚本直接运行最终退款 SQL；中断后应保留备份和日志、使用新后缀重建，不覆盖半成品库。旧版数据库副本和此前日志仍保留，当前候选是 `TokenHubDB_v11_Full261017D`，尚未部署到队友 sh 电脑上。**未执行 Git 提交或推送。**
