# 第9周员工管理与业务复测：真实浏览器证据

本轮数据库为 TokenHubDB_v11_WebEmp26A01。本机 Edge/Playwright 连接实际运行的 Flask 5052 和 SQL Server。
这是自动化真实浏览器截图，不是人工逐张截图或伪造界面；测试支付、Token调用和退款结算均为模拟。

## 总体结果

- 原有顾客/订单/补货/退款流程：22张最新 Edge 截图、42条浏览器事件，PASS。
- 员工管理流程：11张 Edge 截图、10条事件，PASS。管理员新增、修改、重置密码、停用及重新启用；普通员工及游客无权访问；重复账号被拒绝。
- 25项只读 SQL 对账及原业务22张图片的哈希检查：PASS。
- 员工页面初次自动化因密码标签选择器重复匹配而中止，失败记录保存在 employees；选择器修复后在 employees_verified 用新测试账号完成成功复测。旧失败记录不冒充通过。

## 全角色业务图片（第9周重新截图）

| 场景 | 图片 |
|---|---|
| 游客商品目录 | [截图](browser/screenshots/01_游客商品目录.png) |
| 角色登录入口 | [截图](browser/screenshots/02_登录入口.png) |
| 顾客注册表单 | [截图](browser/screenshots/03_顾客注册表单.png) |
| 新顾客自动登录 | [截图](browser/screenshots/04_注册成功自动登录.png) |
| 重复账号异常 | [截图](browser/screenshots/05_重复账号拒绝.png) |
| 密码错误异常 | [截图](browser/screenshots/06_错误密码拒绝.png) |
| 管理员新增商品 | [截图](browser/screenshots/07_管理员新增商品.png) |
| 重复档位异常 | [截图](browser/screenshots/08_商品唯一约束拒绝.png) |
| 管理员新增上游库存 | [截图](browser/screenshots/09_管理员新增库存账号.png) |
| 顾客下单表单 | [截图](browser/screenshots/10_顾客订单表单.png) |
| 待支付订单 | [截图](browser/screenshots/11_顾客待支付订单.png) |
| 模拟支付完成 | [截图](browser/screenshots/12_订单模拟支付成功.png) |
| Token余额 | [截图](browser/screenshots/13_支付后余额.png) |
| 模拟调用扣减 | [截图](browser/screenshots/14_Token调用扣减.png) |
| 退款后的订单 | [截图](browser/screenshots/15_顾客部分退款订单.png) |
| 退款账本待结算 | [截图](browser/screenshots/16_退款金额待结算.png) |
| 跨顾客数据隔离 | [截图](browser/screenshots/17_第二顾客数据隔离.png) |
| 店员补货完成 | [截图](browser/screenshots/18_店员补货完成.png) |
| 店员越权异常 | [截图](browser/screenshots/19_店员无商品管理权限.png) |
| 管理员模拟退款结算 | [截图](browser/screenshots/20_管理员模拟退款结算.png) |
| 游客访问订单401 | [截图](browser/screenshots/21_游客访问订单401.png) |
| 验收结束 | [截图](browser/screenshots/22_验收结束游客界面.png) |

## 管理员工图片（第9周新增）

| 场景 | 图片 |
|---|---|
| 管理员员工列表 | [截图](employees_verified/screenshots/01_管理员员工列表.png) |
| 新增店员表单 | [截图](employees_verified/screenshots/02_新增店员表单.png) |
| 新增店员成功 | [截图](employees_verified/screenshots/03_新增店员成功.png) |
| 重复员工账号被拒 | [截图](employees_verified/screenshots/04_重复店员账号被拒.png) |
| 修改员工姓名 | [截图](employees_verified/screenshots/05_管理员修改店员姓名.png) |
| 重置员工密码 | [截图](employees_verified/screenshots/06_管理员重置密码后.png) |
| 停用员工 | [截图](employees_verified/screenshots/07_店员停用保留记录.png) |
| 重新启用员工 | [截图](employees_verified/screenshots/08_店员重新启用.png) |
| 普通店员无员工管理权限 | [截图](employees_verified/screenshots/09_普通店员没有员工管理入口.png) |
| 游客员工API拒绝 | [截图](employees_verified/screenshots/10_游客不能查看员工列表.png) |
| 新店员登录与权限 | [截图](employees_verified/screenshots/11_新店员可登录但无管理权限.png) |

## 实际日志与验证

- [原业务浏览器 manifest：截图 SHA-256、HTTP 状态及 request_id](browser/manifest.json)
- [员工管理浏览器 manifest：截图 SHA-256、HTTP 状态及 request_id](employees_verified/manifest.json)
- [首次自动化未通过记录（测试选择器错误，已修复）](employees/failure.json)
- [真实 SQL Server 25 项只读对账](database_reconciliation.json)
- [员工管理集成测试脚本](../../../tests/test_employee_management.py)
- [新的第9周阶段报告](../../../report/stage2_report.md)

## 数据与权限原则

员工管理 SQL 存储过程重新校验管理员身份，只返回非敏感员工信息；仅可管理 staff，不可提升为 admin。
禁止物理删除员工：用停用代替删除，历史库存和补货外键保持完整；停用及重置密码立即撤销旧会话。
本轮未验证真实资金结算或普通 Windows 专用受限运行账户；保留早期 WebStage2A02 证据作为上一轮独立验收。
