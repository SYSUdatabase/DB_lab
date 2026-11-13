# 第二阶段展示：运营可视化看板

本页面只扩展第5—9周的 v1.1 Web 系统，供课堂展示阶段成果使用；不包含第10周之后的事务/存储过程作业内容。

## 看板功能与数据口径

- **全量订单、待支付、已支付订单数**：来自当前数据库的 `dbo.Orders`。已支付订单指状态严格为 `paid`；已退款、部分退款分别计入状态图。
- **模拟已付金额**：统计状态为 `paid`、`refunded`、`partially_refunded` 的订单原始金额；这是历史支付额，包含后来退款的订单，不等于净收入。
- **模拟退款金额**：来自 `dbo.RefundLedger.refund_amount`，仅表示模拟业务登记。
- **库存预警**：有效上游账号中，`Inventory.current_quota < UpstreamAccount.safety_threshold` 的个数和前五条明细。
- **订单状态分布**：数据库中保留的全部订单的状态计数。
- **近14天订单趋势**：按数据库服务器本地日期统计 `Orders.created_at`，每天包含零单日期。
- **刷新策略**：店员/管理员打开看板后，每15秒轮询同源接口；可手动刷新。不是数据库推送或外部实时监控。

权限为双层控制：`webapp/services.py` 仅允许 `staff/admin` 访问；SQL 存储过程 `app.Dashboard` 重新检查有效员工会话，不向顾客或游客提供全站统计。由拥有者执行的存储过程负责汇总；运行账户无业务基表直接读取授权。

## 一次性安装与启动（已有数据库）

在项目根目录 PowerShell 中执行（下例选用原人工演示库；**勿在旧验收证据库上无计划地安装或重置数据**）：

```powershell
# 仅首次安装统计过程需要，保持程序与数据库版本一致：
sqlcmd -S "localhost\SQLEXPRESS" -d "TokenHubDB_v11_WebManualA01" -E -C -b -f 65001 -i "sql/app/dashboard.sql"

# 启动网站（本机预览）：
$env:DB_LAB_APP_DATABASE = "TokenHubDB_v11_WebManualA01"
$env:DB_LAB_SERVER = "localhost\SQLEXPRESS"
$env:DB_LAB_SECRET = [Guid]::NewGuid().ToString("N") + [Guid]::NewGuid().ToString("N")
$env:DB_LAB_PREVIEW = "1"
.\.venv\Scripts\python.exe -m webapp
```

浏览器打开 http://127.0.0.1:5050/，用原已创建的 `web_staff` 或 `web_admin` 登录，进入“运营概览”。原数据库登录密码不受上述 `SECRET` 影响。

> 若使用 `tools/app_prepare.py --suffix ...` 从零建立新的 Web 实验库，则会自动安装 `sql/app/dashboard.sql`，不需要单独执行上面的 `sqlcmd`。新库仍需先通过 `DB_LAB_DEMO_PASSWORD` 设置对应的演示登录密码。

## 恢复与证据边界

- 部署前对 `WebManualA01` 进行过 SQL Server 完整 `COPY_ONLY, CHECKSUM` 备份和 `RESTORE VERIFYONLY`。文件在 SQL Server 服务私有备份目录中，普通 Windows 用户可能无法直接访问。
- 看板的统计过程本身只执行 SELECT，不创建订单、不修改库存、不生成模拟交易。
- 现场演示创建/支付订单、补货后，刷新看板即可看到对应数量变化；显示结果必须与当前数据库实际值一致。
- 如果需要反复演练并恢复现场，建议先创建专用展示库并单独备份。不要直接还原覆盖原验收数据库。
- 本功能的局部测试在 `tests/test_dashboard.py`；SQL/权限/实际计数校验采用事务回滚，不保留测试会话或业务写入。


## 启动前准备近14天样例

使用数据库准备身份，在核对目标库后、启动Web前运行。

```powershell
.\.venv\Scripts\python.exe tools/seed_dashboard_recent.py --server $ServerInstance --database $DatabaseName
if ($LASTEXITCODE -ne 0) { throw '近14天样例准备失败' }
```

脚本生成专用顾客dashboard_recent_sample与商品Dashboard Recent Sample。近14天每天1—4笔订单，数量按日历日期固定，记录包含待支付、已支付、取消和退款。订单创建时间覆盖14天，支付、退款使用当前执行时间，由已有过程记账。原有交易不改日期，库存不受影响。

同一日期重复执行不重复加单；跨日执行只补新窗口中缺少的订单。操作键应用锁串行化并发准备，整体事务失败回滚。仅允许v1.1 Web库及数据库准备身份运行，应用运行角色没有样例写入授权。样例关联对象随RunId对应数据库整体清理。
