# 第一阶段 v0.1 AI 使用记录

> 日期：2026-09-30
> AI：GPT-5.6 Sol
> 原则：AI 输出只作为候选实现；以人工业务口径和真实 SQL Server 执行结果作为最终依据。

## 1. AI 建议、人工修改与验证结论

| 项目 | AI 建议 | 人工修改/确认 | 实际验证结论与证据 |
|---|---|---|---|
| 销售统计口径 | paid 订单才计入销售；历史金额使用明细快照 | 确认 pending/cancelled/refunded 不进入销售额 | 85 个 paid 订单、4228.90 元；`query.sql.log`、`verify.sql.log` |
| 全会员统计 | 使用 LEFT JOIN，并把 paid 条件放在 ON | 保留无 paid 订单用户，不把 LEFT JOIN 写成隐式 INNER JOIN | 40 用户、14 人无 paid 订单；截图 06 |
| 商品销售视图 | Products LEFT JOIN paid 明细聚合 | 保留零销量商品 | 10 个商品全部保留；VFY07 逐行双向 EXCEPT 通过 |
| 库存口径 | Inventory 关联 UpstreamAccount | 确认库存是上游账号额度，不是商品件数 | 库存与账号、流水两种算法一致；VFY05 通过 |
| 会员隔离 | 用 `USER_NAME()` 绑定数据库用户与业务 user_id | 不使用调用者可随意设置的 SESSION_CONTEXT；不给会员基表 SELECT | user1 仅 13 单、user2 仅 15 单；R06/R07/R10 与截图 11 |
| 权限设计 | 四角色最小权限，不授予固定高权限角色 | 店员仅更新队列视图 status；店长无 DDL/CONTROL | R01～R13 全 PASS；截图 10 |
| 完整性用例 | 用例驱动器必须验证指定错误号/约束名，而不是“任意报错都算通过” | 保留 C01～C11，合法用例回滚，非法用例匹配错误号和约束名 | C01～C11 全 PASS；截图 08/09、`constraint.sql.log` |
| 跨列约束 | 新增 subtotal、total_tokens、订单支付时间 3 个 CHECK | 使用 `WITH CHECK ADD`，不允许 NOCHECK 绕过已有数据 | 3 个 CHECK 均启用且可信；VFY03 通过 |
| 权限异常处理 | 在事务中 `EXECUTE AS` 做越权测试 | 首次实跑发现 3930；人工改为异常路径先 ROLLBACK 再 REVERT | 修正后 R01～R13 全 PASS；`role.sql.log` |
| 会员集合断言 | 用 CTE 表达预期集合 | 首次实跑出现 SQL Server 156；人工改为表变量 + 双向 EXCEPT | VFY06 通过；`verify.sql.log` |
| 数据复现 | 两个新库执行同一流水线并比较签名 | 使用固定 A/B 库，逐表完整 JSON + SHA-256 | 14 表全部 PASS、mismatches=0；截图 12 |
| 截图证据 | 结果应来自真实执行而非模拟图片 | 使用真实 PowerShell/sqlcmd 窗口执行 `evidence_sql/` 后抓屏；乱码错误改为显示错误号+命中约束名 | 12 张 PNG 已生成并抽查；`result/screenshots/` |

## 2. AI 生成/协助的实现范围

AI 协助生成或整理了：

- `tools/prepare_v01.ps1` 与 `tools/run_v01.ps1`。
- `sql/query.sql`、`view.sql`、`constraint.sql`、`role.sql`、`verify.sql`、`signature.sql`。
- README、SQL 索引、阶段报告、结果证据索引和演示说明。
- 结果截图的证据 SQL 与截图辅助脚本。

AI 没有被视为“验证者”。脚本是否正确，最终通过 SQL Server 2025 Express 的真实退出码、查询结果、错误号、数据签名和截图证据判定。
