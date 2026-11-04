# 第五—九周第二阶段交付记录

本文件只记录第二阶段的当前进度；第 1—4 周和整合前的完整执行过程保留在 [历史 ROADMAP](archive/coursework/week4/ROADMAP_combined_before_stage2.md)。详细技术过程见 [AI 日志](docs/ai_usage_log.md)。

| 阶段 | 主要完成内容 | 对应证据 |
|---|---|---|
| 第 5 周 | ER 模型、主外键和参与约束核验、数据字典、问题清单与独立复核 | [week5](week5/README.md) |
| 第 6 周 | 函数依赖/范式分析、UsagePeriod/UsageSummaryCore 迁移、回归及后续 v1.1 修复 | [week6](week6/README.md)、[v1.0 迁移](sql/v10/migration.sql) |
| 第 7 周 | 数据库基础代码（陈诗翰）、Web 四层结构和受控业务入口 | [sql/app](sql/app/)、[Web 代码](webapp/) |
| 第 8 周 | 顾客注册与输入/角色检查、Web 完整测试、交付整理（阮依成） | [注册](sql/app/register.sql)、[集成测试](tests/test_registration.py)、[组内分工](docs/team_division.md) |
| 第 9 周集成成果 | Edge 真浏览器、正常和异常流程、SQL 只读对账、截图及报告 | [最终验收索引](result/stage2/WebStage2A02/README.md)、[报告](report/stage2_report.md) |

## 2026-10-28 当前自动化验收结果

- 完整新库 `TokenHubDB_v11_WebStage2A02` 构建 PASS；新顾客注册、店员/顾客/管理员权限、订单支付/退款/补货等 **22 张真 Edge 页面截图**，42 条浏览器执行事件。
- `tools/stage2_reconcile.py` SQL Server 只读对账 **25 项 PASS**；订单 #112 金额 12.00 元、Token 135791、消费 50000、回收 85791、应退 7.58 元。
- 账号 #17 扣除 50000；账号 #18 补货实际增加 8000。分别核查库存与变动流水一致。
- 另一个隔离库 `WebSign28A` 的 **66 项 unittest 全部通过，0 失败/0 跳过**，不能将不同数据库的执行结果拼成同一事务现场。
- 历史第 1—4 周文档、原 README、旧报告及旧证据均复制/搬入 `archive/`，保留原文、文件哈希和路径映射；用于新库构建的 `sql/v01/`、工具及测试仍在当前目录。
- `report/render_app_er.py` 与 `report/render_overview_modules.py` 依用户最新要求保留，图和源文件可重新渲染。

## 未完成、不得登记为通过的事项

- [x] 两名组员已实际参与验收：陈诗翰第一名在其环境测试；阮依成第二名亲自检查登录及订单显示，发现缺少注册入口并提出修复。
- [ ] 使用真正受限的 Windows 普通账户启动 Flask/Waitress 服务，运行 `tools/runtime_identity.py` 核验实际 SQL 权限；`DB_LAB_PREVIEW=1` 不算此项。
- [ ] 截图、报告、组内分工在最终提交前由小组成员人工核对、确认版本与姓名，并按要求完成提交。

不执行真实支付、资金退款或真实供应商 API 调用。第 5—9 周提交说明见[根 README](README.md)，不要对既有数据库做 DropExisting 或在历史证据中覆盖数据。


## 2026-11-04 本地临时复现资源清理

- [x] 按精确白名单删除第六周 4 个 W6Replay/W6Auto 数据库、两个仓库外解压目录、两个临时 recheck 日志、3 个 Python 缓存目录及 Ruff 缓存；保留其它 15 个历史/Web 数据库、正式验收证据、迁移 ZIP、.venv 和 instance。
- [x] 根 README 最后一节新增可重复的安全清理流程；四个数据库删除后核验不存在，保留数据库仍 ONLINE；PowerShell Parser、README 链接及 git diff --check 均通过。


## 2026-11-04 WebNewRun01 从空库复现

- [x] 新后缀 `WebNewRun01` 从空 v0.1 创建源库，建库、表、样例数据、CRUD、视图、查询、约束、角色和验证脚本全部 PASS。
- [x] v1.0 迁移 PASS：3394 条汇总、99 个周期键、15 张表、18 条外键、11 个视图。
- [x] v1.1 加固与账务验证 PASS：17 张业务表、20 条可信外键、158 个 Token 批次、3000 条消费引用、11 个 W6 guards，退款账本核验通过。
- [x] Web 数据库安装完成：17 张业务表 + 1 张 Sessions 表；历史修复步骤因新建源库已通过 VFY12/13 且加固验证通过而按设计跳过。
- [ ] 本轮未重新执行 Edge 浏览器 E2E 或普通 Windows 受限账户启动；既有浏览器证据仍以 WebStage2A02 为准。

证据：[源库签名](result/source_WebNewRun01/signature.txt)、[v1.1 完整验证](result/week6/v11/WebNewRun01/validation_verify_v11_full.sql.log)、[Web 构建清单](result/webapp/WebNewRun01/manifest.json)。
