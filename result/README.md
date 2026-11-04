# 第 5—9 周数据库/Web 实验结果索引

| 内容 | 验证材料 |
|---|---|
| 第二阶段 Edge 全角色浏览器及异常截图（22 张） | [最终截图与请求编号](stage2/WebStage2A02/README.md) |
| SQL 订单、退款与库存对账（25 项） | [只读对账 JSON](stage2/WebStage2A02/database_reconciliation.json) |
| Web 全新数据库准备 | [本轮构建日志](webapp/WebStage2A02/) |
| Web 自动化 66 项测试 | [完整测试日志](webapp/WebSign28A/registration_unit_stderr.log) |
| v1.0 迁移与 v1.1 业务回归 | [第六周结果](week6/README.md) |
| 第五周 ER 模型验证 | [第五周结果](week5/README.md) |
| 1—4 周历史旧验证数据 | [归档](../archive/evidence/stage1-legacy/) |

## 第9周最终补充验收（2026-11-04）

- [第9周最新结果、33张真 Edge 截图与 SQL 25项对账](stage2/WebEmp26A01/README.md)
- [第9周员工管理11张截图与请求编号](stage2/WebEmp26A01/employees_verified/manifest.json)
- [完整72项 Python 测试 PASS](stage2/WebEmp26A01/unittest_rerun_stderr.log)
- 原第8周 WebStage2A02 仍为上一轮独立验收记录，不覆盖原始截图或修改旧日志。

## 2026-11-04 旧测试结果精简说明

第9周最终验收以 [WebEmp26A01](stage2/WebEmp26A01/README.md) 为主要证据。清理已无活动文档引用的第6周重复运行日志、临时 recheck 文件、空 stdout 和首次员工管理截图中可由成功复测替代的重复图片；**第一次失败的 failure.json 和 99_失败现场.png 仍保留**。第8周的完整业务浏览器截图、66项测试以及第5/6周有效迁移与回归均未删除。

两套早期注册/业务测试的 v0.1 源库原始日志移动到 [archive/evidence/stage2-legacy](../archive/evidence/stage2-legacy/)，按 SHA-256 校验；对应的原 66 项测试和 22 张浏览器截图仍在 result 目录。完整移除/归档路径、文件大小与原始 SHA-256 见 [本次清理记录](../archive/evidence/stage2-legacy/result_cleanup_20261104.json)。仅整理本地文件，未删除任何 SQL Server 数据库。
