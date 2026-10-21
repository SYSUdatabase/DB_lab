# 第7–9周应用运行与操作手册

第二阶段课程版本为 v1.0，内部数据库基线采用 v1.1。应用使用 Flask/Jinja/JavaScript/pyodbc/Waitress，同源访问，不需要 Node 构建。所有支付、调用、退款结算均为本地模拟。

## 环境与目录

Windows 64位、Python 3.11及以上、SQL Server Express、ODBC Driver 18、ODBC sqlcmd、PowerShell 5.1及以上。SQL Server 时间应为 Asia/Shanghai；本机为 China Standard Time。数据库准备使用有建库、备份、还原权限的 Windows 身份，应用运行另用普通 Windows 账户。

```text
webapp/
  templates/index.html  页面结构
  static/app.js/css    表单、分页、角色导航、友好反馈
  __init__.py         HTTP路由、CSRF、统一异常和请求日志
  services.py         业务授权、身份与输入检查
  dao.py              唯一数据库访问层、参数化调用、连接工作单元
  errors.py           HTTP与SQL错误分类
sql/app/              会话与权限、应用过程、兼容交易适配
tools/app_prepare.py  全新数据库准备
tools/setup_web_runtime.ps1  普通账户与计划任务配置
tests/test_app_*.py / test_web*.py  SQL与HTTP集成检查
```

配置模板：[.env.example](../.env.example)。程序从环境变量读取配置，不自动加载 .env。`instance/` 已忽略，包含本地日志及运行配置，不能提交或共享。数据库及结果目录重名即拒绝，不使用 DropExisting。

## 从新环境准备数据库

在仓库根目录执行，后缀每次换新，必须为 Web 加3–12个字母或数字：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-web.txt
$env:PATH = "$pwd\.venv\Scripts;$env:PATH"
$env:DB_LAB_DEMO_PASSWORD = Read-Host '设置本地样例密码，至少12字节'
.\.venv\Scripts\python.exe tools/app_prepare.py --suffix WebYourRun01
```

密码仅用于本地合成样例，勿输入已有个人密码。四个样例账户使用该密码：顾客 `web_customer`、`web_other`；员工入口中店员 `web_staff`、管理员 `web_admin`。原占位密码账户不用于Web登录，不提供注册与密码找回。

准备工具先执行全部 v0.1 验收和14表签名，再新建 v1.0/v1.1 副本、CHECKSUM备份及VERIFYONLY，运行基础规则、加固、FIFO账本与退款回归，最后安装应用扩展和当前有效账号。干净源库已通过时间与历史余额检查，不调用针对旧异常数据的修复程序。旧源库与既有副本不修改。

结果分别在 `result/source_<后缀>/`、`result/week6/v11/<后缀>/`、`result/webapp/<后缀>/`。失败后保留库和日志、修正代码再换新后缀；不要从中间无序重跑。

## 配置普通 Windows 账户并启动

在 Windows 管理员 PowerShell 中、仓库根目录运行一次：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup_web_runtime.ps1 `
  -DatabaseName TokenHubDB_v11_WebYourRun01 -AccountName TokenHubWeb
```

脚本创建普通本地账户、Windows集成SQL登录与数据库用户，只加入 app_runtime；生成本地运行密钥，设置文件权限，并创建以普通账户运行的计划任务。任务立即启动，系统启动后也启动。访问 [本地应用](http://127.0.0.1:5050/)；监听地址固定127.0.0.1。

脚本不接受已有账户、已有运行配置或同名任务。若权限配置中断，保留错误，先检查已完成阶段；不要删除既有账户或通过赋予db_owner/sysadmin解决。运行账户仅需仓库及Python运行时的读取/目录遍历权限、instance写权限。

`instance/runtime.log` 保存服务启动输出；`instance/webapp.log` 保存请求编号、时间、操作、角色、错误码和结果。日志不包含密码、会话令牌、原始SQL或完整异常参数。运行账户应执行 [身份核对脚本](../tools/runtime_identity.py)，确认sysadmin/db_owner均为0，读取基表、修改商品及DDL均拒绝，商品目录可读。该检查须以该账户实际连接执行，不能用sysadmin的EXECUTE AS结果代替。

当前会话没有Windows管理员权限，因此本轮未创建普通Windows账户；配置脚本已提供，最终账户启动验收仍待执行。

## 开发预览

仅开发核对可使用当前管理身份建立连接后切换为不含登录的 app_runtime_probe；此模式不能替代上述最终账户验收。会话退出前REVERT且禁用ODBC池，避免上下文被连接复用。

```powershell
$env:DB_LAB_APP_DATABASE = 'TokenHubDB_v11_WebYourRun01'
$env:DB_LAB_SECRET = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
$env:DB_LAB_PREVIEW = '1'
.\.venv\Scripts\python.exe -m webapp
```

正常运行未设置预览模式时，应用拒绝sysadmin连接。HTTPS反向代理部署时另设DB_LAB_HTTPS=1以启用Secure Cookie；本阶段不配置公网入口。

## 角色操作

| 身份 | 操作入口与边界 |
|---|---|
| 游客 | 在售商品目录、搜索及登录 |
| 顾客 | 创建含至少一项明细的订单；同商品合并；仅本人pending订单可增改删明细或取消；模拟支付后可查询余额、模拟调用；申请未消费部分退款 |
| 店员 | 商品查询、全部订单/调用/余额查询、取消pending订单；库存查询、创建并完成补货任务；退款账本查询 |
| 管理员 | 店员能力加商品维护、无引用商品删除、上游账号增改及无引用账号删除、空草稿删除、模拟退款结算 |

支付给对应provider的余额和Token批次入账，不扣库存。调用按服务端选中的有效上游账号扣库存，按FIFO扣订单批次。订单价格始终采用首次快照，变价不会追溯修改已购明细。

草稿可以编辑为空，但空单不能支付。已付、已退订单不能直接修改或删除；被引用商品可下架，不能强行删除。新增账号自动产生唯一库存行，库存数字不能任意覆盖，补货增加、调用减少。

退款回收该订单全部可退余额，消费部分不退。退款重复提交返回原记录。管理员登记的SIM编号仅标记本地模拟结算，不表示外部资金划转。

## 测试与故障定位

```powershell
$env:DB_LAB_TEST_DATABASE = 'TokenHubDB_v01_WebYourRun01'
$env:DB_LAB_APP_DATABASE = 'TokenHubDB_v11_WebYourRun01'
# DB_LAB_DEMO_PASSWORD须为本次建库时的样例密码
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\.venv\Scripts\ruff.exe check webapp tools/app_prepare.py tools/browser_qa.py tools/runtime_identity.py tests
.\.venv\Scripts\ruff.exe format --check webapp tools/app_prepare.py tools/browser_qa.py tools/runtime_identity.py tests
```

SQL反例在事务中回滚；HTTP业务流程测试会在指定新实验库增加订单、调用和退款，不用于旧交付库。故障注入测试会在隔离事务中临时创建触发器并回滚；应在无人写入的实验库单独执行。缺少数据库环境变量的测试明确skipped。

浏览器测试使用已安装的Tabbit CLI、[场景脚本](../tools/browser_qa.js)和[执行器](../tools/browser_qa.py)，验证三角色流程；不要求运行应用的普通用户安装Tabbit。前端提示失败时保存请求编号，按日志定位；不复制内部异常到页面。

最终原目录56项自动测试全部通过，无skipped；完整结果见[证据索引](../result/webapp/README.md)。第二名成员独立复现和普通Windows账户最终启动尚未登记；现有自动检查不代表这些事项完成。


应用ER重导出需要可选的matplotlib依赖：安装 "matplotlib>=3.8,<4" 后执行 python report/render_app_er.py。已有SVG/PNG可直接查阅。
