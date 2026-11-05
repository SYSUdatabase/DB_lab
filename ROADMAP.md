# 第五—九周第二阶段交付记录

本文件只记录第二阶段的当前进度；第 1—4 周和整合前的完整执行过程保留在 [历史 ROADMAP](archive/coursework/week4/ROADMAP_combined_before_stage2.md)。详细技术过程见 [AI 日志](docs/ai_usage_log.md)。

| 阶段 | 主要完成内容 | 对应证据 |
|---|---|---|
| 第 5 周 | ER 模型、主外键和参与约束核验、数据字典、问题清单与独立复核 | [week5](week5/README.md) |
| 第 6 周 | 函数依赖/范式分析、UsagePeriod/UsageSummaryCore 迁移、回归及后续 v1.1 修复 | [week6](week6/README.md)、[v1.0 迁移](sql/v10/migration.sql) |
| 第 7 周 | 数据库基础代码（陈诗翰）、Web 四层结构和受控业务入口 | [sql/app](sql/app/)、[Web 代码](webapp/) |
| 第 8 周 | 顾客注册与输入/角色检查、Web 完整测试、交付整理（阮依成） | [注册](sql/app/register.sql)、[集成测试](tests/test_registration.py)、[组内分工](docs/team_division.md) |
| 第9周：陈诗翰 | 完成负责版本的后续测试与更新（按组内确认记录） | [分工](docs/team_division.md) |
| 第9周：阮依成 | 补齐管理员工：新增、改名、密码重置、停用/启用、权限检查；重截业务与员工管理页面并更新报告 | [第9周新证据](result/stage2/WebEmp26A01/README.md)、[报告](report/stage2_report.md) |

## 2026-10-28 当前自动化验收结果

- 完整新库 `TokenHubDB_v11_WebStage2A02` 构建 PASS；新顾客注册、店员/顾客/管理员权限、订单支付/退款/补货等 **22 张真 Edge 页面截图**，42 条浏览器执行事件。
- `tools/stage2_reconcile.py` SQL Server 只读对账 **25 项 PASS**；订单 #112 金额 12.00 元、Token 135791、消费 50000、回收 85791、应退 7.58 元。
- 账号 #17 扣除 50000；账号 #18 补货实际增加 8000。分别核查库存与变动流水一致。
- 另一个隔离库 `WebSign28A` 的 **66 项 unittest 全部通过，0 失败/0 跳过**，不能将不同数据库的执行结果拼成同一事务现场。
- 历史第 1—4 周文档、原 README、旧报告及旧证据均复制/搬入 `archive/`，保留原文、文件哈希和路径映射；用于新库构建的 `sql/v01/`、工具及测试仍在当前目录。
- `report/render_app_er.py` 与 `report/render_overview_modules.py` 依用户最新要求保留，图和源文件可重新渲染。

## 未完成、不得登记为通过的事项

- [x] 两名组员已实际参与验收：陈诗翰第一名在其环境测试；阮依成第二名亲自检查登录及订单显示，发现缺少注册入口并提出修复。
- [x] 使用真正受限的 Windows 普通账户启动 Flask/Waitress 服务，运行 `tools/runtime_identity.py` 核验实际 SQL 权限；`DB_LAB_PREVIEW=1` 不算此项。2026-11-06 由肖懿在新电脑上完成，见下方“新环境从零部署与受限账户验收”。
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
- [ ] 本轮未重新执行 Edge 浏览器 E2E 或普通 Windows 受限账户启动；既有浏览器证据仍以 WebStage2A02 为准。（两项已在 2026-11-06 WebXY1105F 中补做，本条保留为当时记录。）

本轮三个实验数据库、两份批次备份和三个复现证据目录已按 RunId 清理；本节保留构建与验证结果摘要。


## 2026-11-04 第9周新增员工管理

- 陈诗翰继续进行其负责部分的测试和更新。
- 阮依成发现管理端缺少员工管理；新增仅管理员可用的员工列表、创建/改名/重置密码、停用/启用。员工的业务历史通过软停用保存，不允许物理删除。
- 真 Edge 对旧业务重新截图22张，新增员工管理真实截图11张；SQL只读对账25项通过。浏览器操作为AI辅助自动化，区别于组员人工测试。
- 独立测试、日志、异常结果及截图位于 [WebEmp26A01](result/stage2/WebEmp26A01/README.md)。

## 2026-11-04 每次复现按 RunId 清理

- [x] 新增 `tools/cleanup_reproduction.ps1`，以 `Web...` 后缀精确清理 v0.1/v1.0/v1.1 三个数据库、两份 SQL 备份、三个批次结果目录及可再生成缓存；支持 `-WhatIf`、`-Confirm`、`-KeepEvidence`、`-AllowIncomplete`。
- [x] `build_sandbox.py` 在 BACKUP 前记录 `.backup_path.txt`，使中断批次也能找到已创建或部分创建的备份文件。
- [x] README 增加每批次完整清理说明，区分可选受限运行账户/计划任务/SQL 登录/用户配置目录清理；保留 `.venv`、Git、SQL 源码和其他 RunId。
- [x] 新批次备份改为 `result/sql_backups/<RunId>/`，仅向 SQL Server 服务身份授予 Modify；新增 3 项 ACL 单元测试并加入 `.gitignore`。
- [x] 清理脚本区分本批次路径记录与 `msdb` 历史候选，历史候选只接受当前 RunId 的精确文件名，避免已删除的探测备份历史行造成误报。
- [x] Python AST、Ruff、3 项单元测试、PowerShell Parser 通过；三个 `WebNewRun01` 数据库均为 `ONLINE/MULTI_USER`，未发现运行中的 `python -m webapp`。
- [x] 在提升 PowerShell 中完成 WebNewRun01 -WhatIf 盘点并核对数据库、备份和三个结果目录；清单仅包含本批次三个数据库、两份旧格式 .bak 和三个结果子目录。
- [x] 预览清单确认后清理 `WebNewRun01` 三个数据库、两份备份和三个结果目录，逐项核验不存在；保留共享环境、源码、Git 和其它 RunId。
- [x] 清理后只读复核：sys.databases 中已无三个目标库；三个证据目录、批次备份目录、两份新批次备份、两份旧默认目录备份及一份 ACL 探测备份文件均不存在。msdb 保留的备份历史记录仅为元数据。


## 2026-11-06 新环境从零部署与受限账户验收（肖懿）

- [x] 在一台未部署过本项目的 Windows 10 家庭版电脑（SQL Server 2025 Express、Python 3.14）上从空库构建 `WebXY1105F`，全部阶段 PASS。
- [x] 以普通 Windows 账户 `TokenHubWebF` 通过计划任务启动网站；该账户实际连接执行 `tools/runtime_identity.py`：sysadmin=0、db_owner=0，读基表/改商品/DDL 三项拒绝，商品目录可读。SQL 端只属于 `app_runtime`，Windows 端不属于任何本地组，5050 监听进程属主为该账户。
- [x] 对该受限账户运行的服务重跑 Edge E2E：原业务 22 张截图/42 条事件、员工管理 11 张截图/10 条事件 PASS。
- [x] 部署中发现并修正 5 个只在新电脑上出现的问题：回归脚本依赖原电脑的 `TokenHubDB_v01_A`；运行账户缺少批处理登录权限；`instance` 权限设置清空文件 DACL；仓库位于用户目录时运行账户无法进入；PowerShell 5.1 下 Flask 日志使启动脚本中止。改动 4 个已有脚本（新增 11 行、修改 2 行），另新增 35 行的 `tools/batch_logon_right.ps1`；网站代码与 SQL 未改。详见[验收记录](result/stage2/WebXY1105F/README.md)。
- [ ] 员工列表“套餐名称 / 套餐 #undefined”显示问题（第9周已存在）未修改。
- [ ] 截图、报告、组内分工的组员人工核对与独立复现仍未完成，不以本轮自动化结果代替。

- [x] 清理：重启电脑使运行账户用户配置卸载后，删除 TokenHubWeb、TokenHubWebE、TokenHubWebF 三个运行账户及其计划任务、SQL 登录、用户配置和 SeBatchLogonRight 授权，删除各批次数据库与备份，清除仓库根目录上的运行账户 ACE；核对 SeBatchLogonRight 恢复为系统默认三组、5050 无监听。WebXY1105D 曾先单独清理数据库，第二次带 `-RemoveRuntime` 运行时清理脚本因批次备份目录已不存在、回退到 msdb 历史路径检查而中止，D/E 两个账户按脚本相同步骤手动删除，清理脚本未为此修改。
- [ ] 清理脚本对同一批次分两次清理（先数据库、后运行账户）的情况不能重入；配置脚本对整个仓库授予的读取 ACE 在删除账户时不会撤销。两项本轮手动处理，未改代码。
