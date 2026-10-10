# 第五周 ER 设计只读验证证据

- **数据库**：`TokenHubDB_v01_A`（现有数据库；没有创建、删除或 ALTER）。
- **运行日期**：2026-10-10；目标：`LAPTOP-3H5FCR3B` 上的 `localhost\SQLEXPRESS`。
- **SQL 源码**：[readonly_validation.sql](readonly_validation.sql)。仅含 `SET`、`PRINT`、`SELECT`，含必要系统目录只读查询。
- **真实 SQL Server 执行日志**：[readonly_validation.log](readonly_validation.log)。命令返回码为 0。
- **对应的解释及图**：[第五周正式交付](../../week5/README.md) 和 [设计验证](../../week5/design_validation.md)。

## 关键观测数据

| 项目 | 观察值 |
|---|---:|
| 业务表 / 已启用 FK / 第四周新增 CHECK | 14 / 17 / 3 |
| 订单 / 订单明细 / 多明细订单 | 100 / 184 / 68 |
| 多商品样例订单 | 5、11、15、16、17 各三条不同商品明细 |
| 没有明细的订单 / 订单总额或 Token 不匹配 | 0 / 0 |
| 有订单的不同用户数 / 引用不存在用户的订单 | 28 / 0 |
| 没有库存行的上游账号 / 库存与上游配额不一致 | 0 / 0 |
| 产品与上游 provider 不匹配的调用 | 0 |
| OpenAI / Claude / Gemini 的账号数 | 3 / 3 / 2 |
| 低于安全阈值的账号数（按 provider） | 0 / 0 / 2 |
| NULL 的流水操作人 / NULL 的任务指派人 | 3000 / 3 |

这些数值仅是本机此时数据库的**样例事实**。尤其 0 张空订单、0 个缺库存账号，不等于 SQL 约束要求强制如此。验证脚本没有读取凭证、密钥、哈希值及无关数据。


## 自动 QA 记录

[qa.log](qa.log) 是原始自动检查记录；[qa_special_er.log](qa_special_er.log) 是本次更新后的检查，额外验证 17 条非标识性外码线、图中的特殊 ER 注记以及新版链接。均来自执行 `week5/qa_week5.py`：14 表/17 FK 图文一致、SVG/PNG 可解析、文档链接检查通过。Git `diff --check` 返回 0（仅有 Windows 行尾规范提示）。无数据库写入。
