# v1.1 业务 SQL

**本目录为最新业务 SQL 代码**，从已经完成 v1.0 规范化迁移的隔离数据库增量部署。完整结构为 **17 张表、20 条可信外键**。

- **基础业务修复**：`enforce_known_rules.sql`、`record_usage.sql`、`protect_parent_deletes.sql`、`approved_rules.sql`、`registered_order_workflow.sql`。
- **账务加固**：`01_typed_consumption_refs.sql`、`02_managed_usage_v11.sql`、`03_close_write_paths.sql`、`05_managed_restock.sql`。
- **退款与 Token 批次**：`07_refund_schema.sql`、`08_accounting_lots.sql`、`09_refund_workflow.sql`。退款按未消费 Token 比例核算应退金额，一订单唯一退款流水，防重复退款；实际资金转账仍依赖外部支付渠道。
- **回归脚本**：`regression_v11.sql`、`test_*.sql`、`04_regression.sql`、`06_restock_regression.sql`、`10_refund_regression.sql`、`verify_v11_full.sql`、`verify_approved_rules*.sql`。

安装有前后依赖和数据库白名单，**不要逐个手工无序执行**。统一 Python 入口、执行顺序、错误恢复、合成数据修复、[ER 图](../../week6/v11/er_diagram_v11.mmd)、[数据字典](../../week6/v11/data_dictionary_v11.md)和日志都在 [week6/v11](../../week6/v11/README.md)。

从项目根目录完整重建：

```powershell
python -B .\week6\v11\run_full.py --suffix NewV11Run01
```
