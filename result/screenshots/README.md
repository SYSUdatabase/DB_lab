# 截图证据说明

本目录中的 22 张 PNG 均在 sh 电脑上实时执行 SQL Server 查询后抓屏，数据库为 `TokenHubDB_v01_A`，服务器为 `localhost\SQLEXPRESS`。01～12 抓于 2026-09-30，13～22 抓于 2026-10-01。

抓屏方式：调用 `../../tools/capture_evidence.ps1`，该脚本会打开一个最大化 PowerShell 窗口执行 `evidence_sql/` 中对应的 SQL，待结果打印完成后截取主屏幕。

截图不是手工绘制结果；每张图对应的 SQL 位于 `../evidence_sql/`，原始输出位于 `../evidence_logs/`，可逐项核对图中内容与日志是否一致。

## 截图与证明内容

### 2026-09-30

1. `01_database_tables.png`：成功建库、14 张业务表及对象数量。
2. `02_crud_products.png`：商品新增、修改、删除。
3. `03_crud_inventory.png`：上游账号与库存新增、修改、删除。
4. `04_crud_orders.png`：订单与订单明细新增、修改、删除。
5. `05_join_query.png`：多表 JOIN 关键查询。
6. `06_sales_members.png`：商品销售统计和无 paid 订单会员。
7. `07_statistical_views.png`：四类核心统计视图。
8. `08_constraint_legal.png`：合法值、DEFAULT、NULL 正例。
9. `09_constraint_illegal.png`：外键、负价格、跨列 CHECK 反例。
10. `10_role_allowed_denied.png`：不同角色允许/禁止操作。
11. `11_customer_isolation.png`：两个会员之间的数据隔离。
12. `12_reproduction.png`：A/B 两个空库的逐表签名一致。

### 2026-10-01（v0.1 修订后）

13. `13_customer_service.png`：R14 `v_CustomerService` 不含 `password_hash`/`api_key` 且店员可读；R15 店员读 `dbo.Users` 报错 229；R16 会员读 `v_CustomerService` 报错 229。
14. `14_inventory_states.png`：`v_InventoryStatus` 的 `account_state`、`stock_state`、`quota_headroom` 三字段口径，附 `InventoryLog` 变动类型汇总。
15. `15_q09_low_stock.png`：Q09 低库存边界行在事务内产生后回滚，`@@TRANCOUNT=0`，基线行数未变。
16. `16_q10_join_contrast.png`：Q10 INNER/LEFT JOIN 行数对照，商品 10/10、会员 26/40。
17. `17_q11_usage_trend.png`：Q11 日粒度与月粒度趋势，日汇总 token 数与月汇总相等。
18. `18_q12_consumption.png`：Q12 消耗与采购、补货分开统计，最高消耗账号为 `account_id=7`。
19. `19_constraint_c12_c13.png`：C12/C13 重复候选码分别报错 2627，约束名可见。
20. `20_constraint_c14_json.png`：C14 非法 JSON 报错 547，`CK_Roles_permissions_json` 生效。
21. `21_verify_all_pass.png`：直接执行 `sql/verify.sql` 的完整验收输出，VFY01～VFY11 全部 PASS。这张图没有单独的 `evidence_sql` 副本，证据源就是 `sql/verify.sql` 本身，原始输出在 `../evidence_logs/21_verify_all_pass.log`。
22. `22_reproduction_abc.png`：A/B/C 三库 14 张表逐表 SHA-256 签名对照，14/14 MATCH。

## 版本口径

01～12 对应 2026-09-30 的脚本版本：图中显示 9 个视图、`v_InventoryStatus` 的单字段 `stock_state` 口径，以及 C01～C11、R01～R13。13～22 对应 2026-10-01 的 v0.1 修订，覆盖 10 个视图、`account_state`/`stock_state` 拆分、Q09～Q12、C12～C14、R14～R17 和 VFY01～VFY11。