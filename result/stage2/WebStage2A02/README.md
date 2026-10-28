# 第二阶段 Edge 浏览器与 SQL Server 验收证据（2026-10-28）

> **实验库：** TokenHubDB_v11_WebStage2A02；浏览器：Windows Microsoft Edge / Playwright；独立服务地址：127.0.0.1:5051。真实网页、真实 HTTP、真实隔离 SQL Server 数据，不是静态绘图。**这批截图是自动化执行；两名组员已另行实际参与网站验收，证据来源分别登记。**

## 验收结果

- 从空 v0.1 → v1.0 → v1.1 → Web/注册完整构建成功；日志在 [Web 数据库准备](../../webapp/WebStage2A02/) 和 [v1.1](../../week6/v11/WebStage2A02/)。
- 完整浏览器流程 **22 张截图 / 42 条记录，PASS**；每张 PNG 均校验 SHA-256。
- 浏览器运行结束后独立 SQL 数据核对 **25 项 PASS**；[JSON 对账报告](database_reconciliation.json)。
- 交付前再次执行 **10 项静态与动态 QA，全数 PASS**：第5/6周图与文档、旧迁移档案、414条链接、Ruff、真实运行中的网站登录/目录、SQL/PNG对账、JS语法及 Git diff 检查；[逐项日志与退出码](final_qa_manifest.json)。
- 独立测试数据库 WebSign28A 运行的 **66 项 unittest 全部 PASS、0 失败、0 跳过**；[原始测试输出](../../webapp/WebSign28A/registration_unit_stderr.log)。
- 正常流程：游客、注册、管理员商品/库存、顾客订单/支付/消费/退款、店员补货、管理员结算；异常：重复账号、错误密码、重复商品、负数调用、无权限、跨顾客、重复退款、不可删除订单及游客 401。
- 开发预览使用 app_runtime_probe；两名组员已实际参与网站验收（第一名陈诗翰，第二名阮依成），但22张截图来自自动化；真正普通 Windows 受限账户启动尚待验证。支付、API 调用和结算为本地模拟。

## 截图索引（全部为实际 Edge 页面）

| 序号 | 检验场景 | 实际截图 |
|---:|---|---|
| 01 | 游客浏览商品目录 | [查看截图](browser/screenshots/01_游客商品目录.png) |
| 02 | 选择顾客或员工登录 | [查看截图](browser/screenshots/02_登录入口.png) |
| 03 | 普通顾客注册表单 | [查看截图](browser/screenshots/03_顾客注册表单.png) |
| 04 | 新顾客自动登录 | [查看截图](browser/screenshots/04_注册成功自动登录.png) |
| 05 | 重复用户名遭到拒绝 | [查看截图](browser/screenshots/05_重复账号拒绝.png) |
| 06 | 错误密码遭到拒绝 | [查看截图](browser/screenshots/06_错误密码拒绝.png) |
| 07 | 管理员创建商品 | [查看截图](browser/screenshots/07_管理员新增商品.png) |
| 08 | 重复供应商/Token 档位遭到拒绝 | [查看截图](browser/screenshots/08_商品唯一约束拒绝.png) |
| 09 | 管理员新建上游账号 | [查看截图](browser/screenshots/09_管理员新增库存账号.png) |
| 10 | 顾客提交订单表单 | [查看截图](browser/screenshots/10_顾客订单表单.png) |
| 11 | 新订单待支付 | [查看截图](browser/screenshots/11_顾客待支付订单.png) |
| 12 | 模拟支付成功 | [查看截图](browser/screenshots/12_订单模拟支付成功.png) |
| 13 | 支付后 Token 余额 | [查看截图](browser/screenshots/13_支付后余额.png) |
| 14 | 实际 Token 调用 | [查看截图](browser/screenshots/14_Token调用扣减.png) |
| 15 | 部分退款后的订单 | [查看截图](browser/screenshots/15_顾客部分退款订单.png) |
| 16 | 退款账本待结算 | [查看截图](browser/screenshots/16_退款金额待结算.png) |
| 17 | 第二顾客隔离 | [查看截图](browser/screenshots/17_第二顾客数据隔离.png) |
| 18 | 店员补货成功 | [查看截图](browser/screenshots/18_店员补货完成.png) |
| 19 | 店员无法管理商品 | [查看截图](browser/screenshots/19_店员无商品管理权限.png) |
| 20 | 管理员模拟结算 | [查看截图](browser/screenshots/20_管理员模拟退款结算.png) |
| 21 | 游客请求订单返回 401 | [查看截图](browser/screenshots/21_游客访问订单401.png) |
| 22 | 执行结束回到游客首页 | [查看截图](browser/screenshots/22_验收结束游客界面.png) |

## 主要读库结果

| 项目 | 实测数据 |
|---|---|
| 订单 | #112；金额 12.00，Token 135791，最终 partially_refunded |
| 购买/使用/回收 | 购买 135791、使用 50000、退款回收 85791 |
| 应退款 | 7.58 元；settled 只是本地模拟账本状态 |
| 顾客退款后余额 | Other 供应商 0 Token |
| 消费所选上游账号 | #17 Web Other：100000000 → 99950000，库存与流水相等 |
| 新建账号 + 补货 | #18：1000000 + 8000 = 1008000，库存与流水相等 |
| 数据模型 | 18 张表、22 条启用且可信外键 |

完整查询值及验证项见 [database_reconciliation.json](database_reconciliation.json)，其中验收脚本明确区分账号 #17 的消费和账号 #18 的补货，**不混算**。

## HTTP 错误回执与请求标识

| 检查 | HTTP/代码 | request_id（可在服务日志对应查询） |
|---|---|---|
| HTTP POST /usage | 400 / INVALID_INPUT | 46a2c3b8ef12438aaefd0215f34c6ce1 |
| HTTP POST /usage | 409 / BUSINESS_RULE | 70bfe773251e4a5285eac632c079aab2 |
| HTTP GET /orders/112 | 403 / FORBIDDEN | 0b8a48de0b184266942755ec4ea51c17 |
| HTTP POST /products | 403 / FORBIDDEN | 502cee9f963a4d8cbe14043ba0958c57 |
| HTTP DELETE /orders/112 | 409 / BUSINESS_RULE | 82d201cc42994771ad60e1cd0e20f218 |
| Unauthenticated API blocked | 401 / None | — |

## 可追溯原始文件

- [浏览器执行 manifest](browser/manifest.json)：测试动作、状态码、请求编号、每张截图的 SHA-256。
- [SQL 对账 JSON](database_reconciliation.json)：浏览器动作结束后的只读查询结果、截图哈希核验与未验证事项。
- [Web 构建日志](../../webapp/WebStage2A02/)：来源 v0.1 创建、备份/还原、加固、Web SQL 安装。
- [v1.1 数据库日志](../../week6/v11/WebStage2A02/)：核心 SQL 规则与回归。
- [独立 66 测试原始日志](../../webapp/WebSign28A/registration_unit_stderr.log)。
- [本次实验报告](../../../report/stage2_report.md)；[手动验收空白清单](../../../docs/stage2_acceptance.md)。

**验收边界：** 截图是由真实 Edge 浏览器自动采集。未验证真实支付/真实外部模型 API，两名组员实际网站验收已登记，但未验证专用受限 Windows 运行账户；上述未执行事项不得写成 PASS。
