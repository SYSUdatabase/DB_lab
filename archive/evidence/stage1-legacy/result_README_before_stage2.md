# 当前验收与证据

2026-10-02 修复后的两个新空库 TokenHubDB_v01_FinalA/B 完整运行通过。C01～C14、R01～R17、VFY01～VFY14 全 PASS；Q01～Q12 成功执行并有独立业务核对。注册前订单/调用、到期后消费、provider 不匹配和历史负余额均为 0。

## 完整复现

- [FinalA 流水线](run_final_A/console.log)、[FinalB 流水线](run_final_B/console.log)
- [FinalA 验收](run_final_A/verify.sql.log)、[FinalB 验收](run_final_B/verify.sql.log)
- [FinalA 签名](run_final_A/signature.txt)、[FinalB 签名](run_final_B/signature.txt)

14 表签名一致；销售额 4228.90、paid 85 单、售出 Token 92950000。旧版 A/B/C、旧截图和首次实施尝试分别保存在 archive/evidence 与 archive/implementation-attempts，不计为当前正式证据。

## 22 组证据与 26 张分页图片

真实 sqlcmd 输出在屏幕外实际 WinForms 控件中分页捕获，完整 UTF-16 日志另存；不是人工填写数据或 SSMS 整屏截图。21 的最后一页完整显示 VFY10～VFY14 与最终 PASS。每个证据脚本都有结果或指定错误断言，工具检测执行失败。

| SQL | 日志 | 图片 |
|---|---|---|
| [01_database_tables](evidence_sql/01_database_tables.sql) | [log](evidence_logs/01_database_tables.log) | [01_database_tables](screenshots/01_database_tables.png) |
| [02_crud_products](evidence_sql/02_crud_products.sql) | [log](evidence_logs/02_crud_products.log) | [02_crud_products](screenshots/02_crud_products.png) |
| [03_crud_inventory](evidence_sql/03_crud_inventory.sql) | [log](evidence_logs/03_crud_inventory.log) | [03_crud_inventory](screenshots/03_crud_inventory.png) |
| [04_crud_orders](evidence_sql/04_crud_orders.sql) | [log](evidence_logs/04_crud_orders.log) | [04_crud_orders](screenshots/04_crud_orders.png) |
| [05_join_query](evidence_sql/05_join_query.sql) | [log](evidence_logs/05_join_query.log) | [05_join_query](screenshots/05_join_query.png) |
| [06_sales_members](evidence_sql/06_sales_members.sql) | [log](evidence_logs/06_sales_members.log) | [06_sales_members](screenshots/06_sales_members.png) |
| [07_statistical_views](evidence_sql/07_statistical_views.sql) | [log](evidence_logs/07_statistical_views.log) | [07_statistical_views](screenshots/07_statistical_views.png) |
| [08_constraint_legal](evidence_sql/08_constraint_legal.sql) | [log](evidence_logs/08_constraint_legal.log) | [08_constraint_legal](screenshots/08_constraint_legal.png) |
| [09_constraint_illegal](evidence_sql/09_constraint_illegal.sql) | [log](evidence_logs/09_constraint_illegal.log) | [09_constraint_illegal](screenshots/09_constraint_illegal.png) |
| [10_role_allowed_denied](evidence_sql/10_role_allowed_denied.sql) | [log](evidence_logs/10_role_allowed_denied.log) | [10_role_allowed_denied_p01](screenshots/10_role_allowed_denied_p01.png), [10_role_allowed_denied_p02](screenshots/10_role_allowed_denied_p02.png) |
| [11_customer_isolation](evidence_sql/11_customer_isolation.sql) | [log](evidence_logs/11_customer_isolation.log) | [11_customer_isolation_p01](screenshots/11_customer_isolation_p01.png), [11_customer_isolation_p02](screenshots/11_customer_isolation_p02.png) |
| [12_reproduction](evidence_sql/12_reproduction.sql) | [log](evidence_logs/12_reproduction.log) | [12_reproduction](screenshots/12_reproduction.png) |
| [13_customer_service](evidence_sql/13_customer_service.sql) | [log](evidence_logs/13_customer_service.log) | [13_customer_service_p01](screenshots/13_customer_service_p01.png), [13_customer_service_p02](screenshots/13_customer_service_p02.png) |
| [14_inventory_states](evidence_sql/14_inventory_states.sql) | [log](evidence_logs/14_inventory_states.log) | [14_inventory_states](screenshots/14_inventory_states.png) |
| [15_q09_low_stock](evidence_sql/15_q09_low_stock.sql) | [log](evidence_logs/15_q09_low_stock.log) | [15_q09_low_stock](screenshots/15_q09_low_stock.png) |
| [16_q10_join_contrast](evidence_sql/16_q10_join_contrast.sql) | [log](evidence_logs/16_q10_join_contrast.log) | [16_q10_join_contrast](screenshots/16_q10_join_contrast.png) |
| [17_q11_usage_trend](evidence_sql/17_q11_usage_trend.sql) | [log](evidence_logs/17_q11_usage_trend.log) | [17_q11_usage_trend](screenshots/17_q11_usage_trend.png) |
| [18_q12_consumption](evidence_sql/18_q12_consumption.sql) | [log](evidence_logs/18_q12_consumption.log) | [18_q12_consumption](screenshots/18_q12_consumption.png) |
| [19_constraint_c12_c13](evidence_sql/19_constraint_c12_c13.sql) | [log](evidence_logs/19_constraint_c12_c13.log) | [19_constraint_c12_c13](screenshots/19_constraint_c12_c13.png) |
| [20_constraint_c14_json](evidence_sql/20_constraint_c14_json.sql) | [log](evidence_logs/20_constraint_c14_json.log) | [20_constraint_c14_json](screenshots/20_constraint_c14_json.png) |
| [21_verify_all_pass](evidence_sql/21_verify_all_pass.sql) | [log](evidence_logs/21_verify_all_pass.log) | [21_verify_all_pass_p01](screenshots/21_verify_all_pass_p01.png), [21_verify_all_pass_p02](screenshots/21_verify_all_pass_p02.png) |
| [22_two_db_signature](evidence_sql/22_two_db_signature.sql) | [log](evidence_logs/22_two_db_signature.log) | [22_two_db_signature](screenshots/22_two_db_signature.png) |

## 复核边界

签名只证明业务行内容相同；对象定义、identity 分配状态、权限不包含在行签名内。对象与权限另有 SQL 验收。反例与重复执行复核位于 recheck。第二名成员独立复现仍待实际登记。

[正式入口](../README.md)、[旧材料说明](../archive/README.md)、[测试说明](../tests/README.md)。
