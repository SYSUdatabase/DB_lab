# 截图证据说明

本目录中的 12 张 PNG 均在 2026-09-30 从 sh 电脑实时执行 SQL Server 查询后抓取，数据库为 `TokenHubDB_v01_A`，服务器为 `localhost\SQLEXPRESS`。

截图不是手工绘制结果；每张图对应的 SQL 位于 `../evidence_sql/`，原始输出位于 `../evidence_logs/`。

## 截图与证明内容

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

如果课程明确要求 SSMS GUI 风格截图，可以在不改变 SQL 的前提下，用同目录 `evidence_sql/` 在 SSMS 中再次执行并补充截图；当前 PNG 已经是真实 SQL Server 执行结果证据。
