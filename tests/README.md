# 第二阶段数据库与 Web 测试（第5—9周）

本目录保留 v0.1 基线验证、v1.0/v1.1 数据库回归和第7—9周的 Web 登录、注册、订单、库存、权限、事务和故障测试。第一阶段旧说明已保存在 [archive](../archive/coursework/week4/tests_README_old_v01.md)，原有 22 项测试日志已移到 [历史结果](../archive/evidence/stage1-legacy/recheck/)，不将历史记录作为当前最终验收。

## 当前有效测试结果

- [66 项 Python 单元与集成测试，0 失败、0 跳过](../result/webapp/WebSign28A/registration_unit_stderr.log)。
- [真实 Edge 浏览器流程：22 张截图、42 条操作及错误码](../result/stage2/WebStage2A02/README.md)。
- [25 项 SQL Server 读库对账、截图 SHA-256 核验](../result/stage2/WebStage2A02/database_reconciliation.json)。
- [第六周迁移回归](../result/week6/README.md)。

## 在新实验库复测

先按照 [根 README](../README.md) 创建从未使用过的新后缀（例如 WebNewRun01），不要重建已有数据或在当前手动测试用的 WebManualA01 中执行自动测试。

在 PowerShell 中设置 DB_LAB_TEST_DATABASE 为 TokenHubDB_v01_WebNewRun01，DB_LAB_APP_DATABASE 为 TokenHubDB_v11_WebNewRun01，DB_LAB_PREVIEW 为 1，并设置对应的 DB_LAB_DEMO_PASSWORD、随机 DB_LAB_SECRET。进入项目根目录执行：

    .\.venv\Scripts\python.exe -m unittest discover -s tests -v
    .\.venv\Scripts\ruff.exe check webapp tests tools

test_registration.py 覆盖顾客注册、格式/重复账号/CSRF/角色检查及注册后登录；test_app_sql.py 验证 SQL 授权；test_app_faults.py 验证事务失败回滚；test_webapp.py 等覆盖 Web API 和角色业务。旧 test_evidence_tool.py 是 v0.1 证据工具正反例，会在 result/recheck 创建临时输出，不是第二阶段截图。

**成员验收：** 第一名陈诗翰在其环境测试；第二名阮依成亲自登录当前网站并核对订单，发现注册缺失并要求补齐。22 张截图是自动化补充证据，不代表成员逐张手动截图。
