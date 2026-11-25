# 第13周后补货状态与 Web 冲突提示修复：反例和增量升级

WebW13Restock1 是从修复前代码新建的独立测试批次，用于复现并验证用户在第13周后的业务复查反馈。

| 步骤 | 结果 |
|---|---|
| 旧版从空库构建 | [prepare.log](prepare.log)，通过 |
| 首轮反例 | [red.log](red.log)，4个测试失败；样例 Other 无对应商品，触发53313 |
| 修正测试供应商（改用已销售的 OpenAI）后复现 | [red_corrected.log](red_corrected.log)，4个测试、9处断言失败；未到期 depleted 补货后仍为 depleted，6种错误映射不满足要求 |
| 重放增量脚本 | [upgrade.log](upgrade.log)，通过 |
| 修复后专项复验 | [green.log](green.log)，5项通过、0跳过，3.391秒 |

专项用例覆盖 active、depleted、suspended、已到期和 expired 状态，检查账号总额度、已用额度、当前库存、可售额度、流水、审计、补货单及失败回滚；通过 Flask 测试客户端与 SQL 实际交互核对重复支付、空订单、可售不足、已取消订单、重复入库及关闭单据的错误提示。没有运行浏览器界面验收。

当前完整代码与测试另见 [补货事务](../../../sql/week12/restock_transaction.sql)、[专项测试](../../../tests/test_restock_feedback.py)。
