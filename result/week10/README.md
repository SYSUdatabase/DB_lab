# 第10周验收证据

| 项目 | 证据与状态 |
|---|---|
| 原业务基线75项 | [WebW10Base01](WebW10Base01/unittest_attempt2.log)，通过 |
| 最终空库构建 | [WebW10Final03](WebW10Final03/prepare.log)，完整准备通过 |
| 全量115项 | [完整测试](WebW10Final03/full_unittest.log)，0失败/错误/跳过 |
| 周次40项逐例 | [结果JSON](W10FinalVerify03/results.json)，含输入与断言预期/实际，全部通过 |
| SQL调用回归 | [日志](WebW10Final03/sql_regression.log)，通过 |
| 新页面与响应丢失重试 | [10张截图清单](WebW10Final03/browser_attempt02/manifest.json)，通过 |
| 员工管理 | [11张截图清单](WebW10Final03/employee_browser_attempt01/manifest.json)，通过 |
| 旧业务追加浏览器 | [失败现场](WebW10Final03/legacy_browser_attempt01/failed.json)，补货按钮精确定位冲突，18张过程/失败截图保留；脚本定位已修复，完整重跑待补做 |
| 安装回滚 | [强制失败后的检查](WebW10Rollback1/rollback_result.json)，通过 |
| 账务一致性 | [计数与异常检查](WebW10Final03/accounting_checks.json)，19表26FK，各异常计数0 |
| 普通Windows身份 | [权限预检](WebW10Final03/runtime_preflight.json)，当前令牌未提升，待补做 |
| 服务关闭 | [关闭记录](WebW10Final03/shutdown.json)，5052无监听 |

WebW10Dev01和SqlTestsAttempt01至07保留开发、失败与修复过程。WebW10Final01保存浏览器筛选修复等尝试，WebW10Final02保存114项测试中发现并修复的授权顺序问题。不同库、不同尝试的结果分别保存。

原始构建证据位于result/source_WebW10*/、result/week6/v11/WebW10*/和result/webapp/WebW10*/，包含迁移回归及安装前后8表业务校验。备份按现有规则保存在Git忽略目录，凭据位于Git忽略的instance。未清理实验数据库。
