# 第二阶段最终实验结果

- [WebStage2A02 真实 Edge 截图、异常结果及 SQL 对账](WebStage2A02/README.md)。
- [浏览器原始事件及 PNG SHA-256](WebStage2A02/browser/manifest.json)。
- [数据库对账原始 JSON](WebStage2A02/database_reconciliation.json)。

自动化测试不是人工签收；课程报告见 [第二阶段报告](../../report/stage2_report.md)。

## 第9周员工管理与重新截图

- [第9周最新浏览器、接口、SQL及错误结果](WebEmp26A01/README.md)：原业务重新截图22张，员工管理新图11张，SQL25项核对通过，72项新全量测试通过。
- [原第8周旧证据](WebStage2A02/README.md)继续保留。

## 新环境从零部署与受限账户验收（2026-11-06）

- [WebXY1105F 验收记录](WebXY1105F/README.md)：新电脑从空库部署，普通 Windows 账户实际连接的权限核对，受限账户运行的服务上原业务 22 张、员工管理 11 张 Edge 截图。
- 部署中各次失败的现场：[WebXY1105C](WebXY1105C/runtime/first_start_failure.json)、[WebXY1105D](WebXY1105D/runtime/first_start_failure.json)、[WebXY1105E](WebXY1105E/runtime/first_start_failure.json)；WebXY1105B 的回归失败日志在 [week6/v11](../week6/v11/WebXY1105B/regression_v11.sql.log)。

## 2026-11-06 最新补充：界面修复与75项完整回归

- [全新隔离数据库 WebFinal1106A：75项 unittest 全通过、0失败、0跳过](WebFinal1106A/README.md)。
- [修复后的真实 Edge 员工姓名列与商品列表截图](WebEmp26A01/ui_fix_20261106/manifest.json)；旧业务截图和原始哈希仍保留。
- [新电脑受限 Windows 运行身份与权限验收](WebXY1105F/README.md)；详细结论和截图见[最新阶段报告第9节](../../report/stage2_report.md)。
