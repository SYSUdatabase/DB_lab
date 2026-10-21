# 第7–9周应用证据

## 数据库准备

- Web261021A：干净v0.1通过；基础v1.1回归误读旧A跨库基线而失败，保留日志。
- Web261021B：基线及加固通过；退款子进程使用系统Python缺少pyodbc，保留日志。
- Web261021C：原v1.1完整验证通过；应用安装初次缺SET选项、第二次使用保留字Execute失败，随后修正。11项SQL测试通过见[08_app_sql_tests.log](Web261021C/08_app_sql_tests.log)，9项API测试通过见[09_api_second.log](Web261021C/09_api_second.log)。
- Web261021D：全新源库→备份校验→v1.0→v1.1→应用扩展→样例账户，一次命令成功；[manifest.json](Web261021D/manifest.json)。原v1.1日志在[第六周结果](../week6/v11/Web261021D/)。

## 测试结论

[D全量测试](Web261021D/04_all_tests.log)：49项通过，无失败/跳过。包含原22项、应用SQL11项、HTTP业务11项、HTTP边界5项。

测试通过实际降为app_runtime_probe或事务中创建的无登录用户验证SQL权限，覆盖18表各SELECT/INSERT/UPDATE/DELETE拒绝及DDL/旧过程拒绝。它不是普通Windows账户登录验收；本轮无Windows管理员权限，专用账户未创建，最终启动验证仍待完成。

浏览器首轮超时回执保存于C：登录、下单、支付成功后，调用选择框隐式标签包含选项文字，精确定位失败；控件增加明确aria-label后继续重测。浏览器最终结果及故障注入证据在完成后追加。

API测试会在新实验库形成合成订单、调用与退款；SQL单项反例回滚。未删除旧库或覆盖历史证据，未执行Git提交或推送。

## 最终补充

- [故障/锁竞争测试](Web261021D/05_fault_tests.log)：5项通过，支付、调用、补货、退款中途失败恢复18表基准，竞争消费观察到数据库锁等待。
- [三角色浏览器回执](Web261021C/18_browser_fourth.json)：7段操作通过；[桌面截图](Web261021C/desktop.png)、[窄屏截图](Web261021C/mobile.png)已目视；窄屏主操作按钮随后按布局检查换行。
- 完整[应用ER可编辑源](../../report/er_diagram_app.mmd)、[SVG](../../report/er_diagram_app.svg)、[PNG](../../report/er_diagram_app.png)，18实体22外键，已目视。
- 最终审查发现断线时清理异常可能覆盖503，新增反例先失败后通过；另补登录kind类型检查。[原目录最终56项测试](Web261021D/08_original_final_tests.log)全部通过，无skipped；Ruff check/format、JS语法、PowerShell解析及144条本地链接检查通过。
- SQL公共操作名称共24种；早期过程记录中的26为统计误差，接口清单以webapp/services.py及sql/app/install.sql为准。
- 普通Windows运行账户及第二名组员独立复现尚待完成。当前身份不在本地管理员组，无法自行创建本地账户或配置计划任务，部署脚本与身份检查已备齐。

[原目录D三角色浏览器完整流程](Web261021D/09_original_browser.json)：7段检查全部PASS，已使用合回后的代码。服务当前以本地受限SQL预览运行，普通Windows账户部署待管理员步骤。
