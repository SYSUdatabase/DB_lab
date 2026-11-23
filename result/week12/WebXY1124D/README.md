# 第12周商品分类自动维护修正与复测（WebXY1124D）

2026-11-23 根据人工发现的问题修正商品分类映射维护：原实现只在第12周安装时为已有商品建立映射，后续新增、修改或删除商品不会同步更新。此次将维护逻辑放在 SQL Server 数据库层，Web 与直接 SQL 写入共用同一套规则。

## 改动

- `sql/week12/category.sql`：`w12.ProductCategoryAssignments.product_id` 外键增加 `ON DELETE CASCADE`，商品删除成功时自动清除分类映射。
- `sql/week12/category.sql`：新增 `dbo.trg_W12_ProductCategoryAssignments`，在 `dbo.Products` 的 INSERT、UPDATE 后按供应商和 Token 容量创建或更新映射。
- 分类规则：OpenAI 按 `token_amount <= 100000` 分到分类 8，否则分类 9；Claude、Gemini、Other 分别映射到分类 5、6、7。
- `w12.fn_CategoryDescendants` 保持不变；递归查询通过映射表连接商品，因此能读取最新分类归属。
- 新增 `sql/week12/test_category_maintenance.sql`，使用事务内临时商品验证后回滚，不留下测试商品。

## 构建与验证

新库 `TokenHubDB_v11_WebXY1124D` 由 `tools/app_prepare.py --suffix WebXY1124D --with-week10 --with-week11 --with-week12` 从空库构建，各安装步骤退出码 0。构建清单和安装日志见 [app_prepare 证据](../../webapp/WebXY1124D/manifest.json)。

| 检查 | 结果 | 证据 |
|---|---|---|
| 商品分类自动维护 | 6/6 通过，包含新增、容量变化、Claude/Gemini/Other 供应商变化、删除级联清理 | [category_maintenance.log](category_maintenance.log) |
| 第11周触发器 | 14/14 通过，`@@TRANCOUNT=0` | [test_trigger.log](test_trigger.log) |
| 第12周事务 | 14/14 通过，`@@TRANCOUNT=0` | [test_transactions.log](test_transactions.log) |
| 窗口查询 | 退出码 0 | [window_query.log](window_query.log) |
| 递归查询 | 退出码 0 | [recursive_query.log](recursive_query.log) |
| 全量 unittest | 126 项通过，0 失败、0 错误、0 跳过 | [full_unittest.log](full_unittest.log) |
| Ruff | 检查通过，38 个文件格式符合要求 | [ruff.log](ruff.log) |

分类自动维护测试逐项确认递归函数能够找到商品所属分类，且自动映射结果为叶子分类。删除用例确认商品行与 `ProductCategoryAssignments` 行均为 0。触发器日志中的本机 SQL 登录标识已作脱敏处理；A2 测试仍验证审计记录中的登录名与 `ORIGINAL_LOGIN()` 一致。

清理：`tools/cleanup_reproduction.ps1 -Suffix WebXY1124D -KeepEvidence -Confirm:$false` 核验通过，三个测试数据库与本批次 SQL 备份已删除，证据目录保留。
