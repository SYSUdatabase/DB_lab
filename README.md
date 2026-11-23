# TokenHub：第三阶段（第10—13周）数据库编程与事务处理

本阶段提交重点为**第10周存储过程与函数、第11周触发器与窗口查询、第12周递归查询和业务事务**。第13周并发控制实验仍待完成。既有数据库及 Web 基础代码只作为运行依赖，阶段报告和证据以第10周及以后为准。

> **重要**：新建第三阶段数据库时必须使用 `--with-week10 --with-week11 --with-week12`，否则只会安装基础业务对象，缺少第10—12周扩展。

## 第三阶段成果与证据

| 周次 | SQL与业务成果 | 提交及核验材料 |
|---|---|---|
| **10** | 销售统计、库存调整存储过程；补货量、销售汇总、折扣函数；库存校正记录表 | [procedure.sql](sql/week10/procedure.sql)、[function.sql](sql/week10/function.sql)、[报告](report/week10_report.md)、[40项逐例验证](result/week10/W10FinalVerify03/results.json) |
| **11** | 库存审计和订单完成规则触发器；排名、累计值、移动平均三种窗口查询 | [trigger.sql](sql/week11/trigger.sql)、[window_query.sql](sql/week11/window_query.sql)、[报告](report/week11_report.md) |
| **12** | 递归分类及商品分类自动维护；订单完成、补货入库事务；提交、回滚和重复调用验证 | [recursive_query.sql](sql/week12/recursive_query.sql)、[事务测试](sql/week12/test_transactions.sql)、[报告](report/week12_report.md) |
| **13** | 锁等待、隔离级别、死锁实验 | 尚待完成 |

第10周专项验证 **40项通过**。最新隔离验收批次 `WebXY1124D` 中，第12周商品分类维护 **6/6**、第11周触发器 **14/14**、第12周事务 **14/14**，全量 Python **126项通过、0跳过**；[原始验收记录](result/week12/WebXY1124D/README.md)。

[第三阶段组内分工](docs/team_division.md) · [AI使用文档](docs/ai使用文档.md) · [AI详细日志](docs/ai_usage_log.md)

## 第10周对象及人工核验

第10周在已有Web业务基础上安装增量，数据库为19张表、26条可信外键。SQL过程/函数说明与SELECT例子见[第10周SQL](sql/week10/README.md)，结构模型见[第10周ER](report/er_diagram_week10.png)。

首次准备在原项目根目录执行，`WebW10Your01`须换为未使用的后缀。

```powershell
# 在项目根目录运行
$env:DB_LAB_DEMO_PASSWORD = Read-Host '设置本轮实验密码'
.\.venv\Scripts\python.exe tools/app_prepare.py --suffix WebW10Your01 --with-week10
```

新建的第10周库会在基础业务库上安装对应的存储过程、函数和库存校正记录。

每次人工核验前，在终端A选择已准备的数据库并启动。

```powershell
# 在项目根目录运行
if (Get-NetTCPConnection -LocalPort 5050 -State Listen -ErrorAction SilentlyContinue) {
    throw '5050已有监听，请先核对对应服务'
}
$env:DB_LAB_APP_DATABASE = 'TokenHubDB_v11_WebW10Your01'
$env:DB_LAB_PREVIEW = '1'
$env:DB_LAB_PORT = '5050'
$env:DB_LAB_SECRET = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
.\.venv\Scripts\python.exe -m webapp
```

终端B检查HTTP就绪，然后访问 `http://127.0.0.1:5050/`。再次启动时使用已有数据库，准备脚本用于新批次构建。

```powershell
$homeResponse = Invoke-WebRequest 'http://127.0.0.1:5050/' -UseBasicParsing
if ($homeResponse.StatusCode -ne 200) { throw '首页尚未就绪' }
$catalog = Invoke-RestMethod 'http://127.0.0.1:5050/api/v1/products'
if ($catalog.code -ne 'OK') { throw '商品接口检查失败' }
```

| 身份 | 操作 | 预期 |
|---|---|---|
| 游客 | 浏览商品，直接访问销售统计API | 商品可读，统计401 |
| 管理员web_admin | 建Other商品P，价格200，套餐Token取未使用且能被4整除的T，每套餐上游消耗100 | 记录P与T，商品创建成功 |
| 管理员 | 建Other上游账号A，总额度1000、安全阈值200、有效期为将来；从库存校正记录新建+300，原因必填 | 可用量1300，总额度1300，记录操作编号与键 |
| 管理员 | 同一校正表单点击“重试原校正请求” | 返回同一记录，额度仍1300；新增调整使用“新建校正操作” |
| 店员web_staff | 销售统计选择起止日；补货任务计算P/A建议，最低2000、目标3000 | 统计可查，建议1700；管理员校正入口不可用，直接API403 |
| 店员 | 按建议创建任务，实际完成填写100 | 创建时库存1300，完成后1400，按实际量增加 |
| 新注册顾客 | 注册并登录新顾客，以P创建一件订单，打开详情 | 原价200、优惠10、成交190，规则amount-v1；草稿改数量会由SQL重算 |
| 顾客 | 支付、消费T/4、申请退款 | 发放T、消费T/4、回收3T/4，应退142.50；记录中途余额 |
| 顾客 | 重复退款；直接访问销售或库存校正API | 退款返回已有项，越权403 |
| 管理员 | 查看销售统计和退款账本，登记模拟结算 | 本商品销量1、成交190，退款后仍保留成交额；应退款142.50 |

顾客使用全新账户可使FIFO批次和上述数量一致。调用账号由服务端选择，库存扣减应按调用记录的account_id核对。角色和接口权限继续由第三阶段回归及人工核验确认。

金额阶梯为满100元优惠5%、满500元优惠10%，每行四舍五入至分，订单金额取折后明细之和。销售日期含首尾两天，按paid_at统计，成交额包含后续退款订单。

核验结束后先保存对象编号、金额、截图和请求编号，在页面退出登录。回到终端A按Ctrl+C并等待提示符返回，再在终端B确认端口释放。

```powershell
if (Get-NetTCPConnection -LocalPort 5050 -State Listen -ErrorAction SilentlyContinue) {
    throw 'Web服务尚未关闭，请核对终端A进程'
}
'5050端口已释放'
```

普通Windows账户部署与计划任务启停沿用[应用手册](docs/webapp.md)。第10周受限SQL用户模拟测试已覆盖，普通Windows身份执行新增入口的验收状态见[运行权限记录](result/week10/WebW10Final03/runtime_preflight.json)。

完整测试使用专用隔离库，配置对应的DB_LAB_APP_DATABASE、DB_LAB_WEEK10_DATABASE、DB_LAB_TEST_DATABASE及实验密码后执行。

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\.venv\Scripts\python.exe tools/week10_verify.py --database $env:DB_LAB_WEEK10_DATABASE --run-id W10YourVerify01
```

浏览器验收和ER重导需要额外QA依赖。

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-qa.txt
.\.venv\Scripts\python.exe tools/week10_browser.py --url 'http://127.0.0.1:5050' --evidence result/week10/YourNewRun/browser
.\.venv\Scripts\python.exe report/render_week10_er.py
```

## 第11—12周增量与验证

第11、12周增量依次装在第10周之后，新库一次构建：

```powershell
$env:DB_LAB_DEMO_PASSWORD = Read-Host '设置本轮实验密码'
.\.venv\Scripts\python.exe tools/app_prepare.py --suffix WebW12Your01 --with-week10 --with-week11 --with-week12
```

`WebW12Your01` 须换为未使用的后缀。建库后按 [第11周 SQL](sql/week11/README.md) 与 [第12周 SQL](sql/week12/README.md) 的命令运行测试脚本和只读查询；`test_category_maintenance.sql` 使用事务内临时商品并回滚，`test_transactions.sql` 会写入新的测试商品、订单和补货单，因此所有写入测试只在专用实验库上运行。全量 Python 测试另设 `DB_LAB_WEEK12_DATABASE` 指向同一 v1.1 库，其余变量同第10周。用完按下文“每次复现后的清理”删除本批次。

## 第三阶段从空库复现

运行要求：Windows、Python 3.11+、SQL Server Express、ODBC Driver 18、PowerShell、`sqlcmd`；建库账号须有创建及备份还原实验库的权限。以下命令均在仓库根目录运行，用**从未使用的新后缀**创建隔离实验库。

```powershell
if (-not (Test-Path .venv/Scripts/python.exe)) { python -m venv .venv }
.\.venv\Scripts\python.exe -m pip install -r requirements.txt

$ServerInstance = 'localhost\SQLEXPRESS'
$Suffix = 'Web' + (Get-Date -Format 'MMddHHmmss')
$env:DB_LAB_DEMO_PASSWORD = Read-Host '设置本轮实验密码'
.\.venv\Scripts\python.exe tools/app_prepare.py --server $ServerInstance --suffix $Suffix --with-week10 --with-week11 --with-week12
if ($LASTEXITCODE -ne 0) { throw '第10—12周数据库准备失败' }

$env:DB_LAB_SERVER = $ServerInstance
$env:DB_LAB_TEST_DATABASE = "TokenHubDB_v01_$Suffix"
$env:DB_LAB_APP_DATABASE = "TokenHubDB_v11_$Suffix"
$env:DB_LAB_WEEK10_DATABASE = $env:DB_LAB_APP_DATABASE
$env:DB_LAB_WEEK12_DATABASE = $env:DB_LAB_APP_DATABASE
$env:DB_LAB_PREVIEW = '1'
$env:DB_LAB_SECRET = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
```

建库后按各周 [第10周](sql/week10/README.md)、[第11周](sql/week11/README.md)、[第12周](sql/week12/README.md) 的调用与测试说明运行。数据库测试会修改实验数据，**只在本轮隔离库运行**：

```powershell
sqlcmd -S $ServerInstance -d $env:DB_LAB_APP_DATABASE -E -C -b -f 65001 -i sql/week11/test_trigger.sql
sqlcmd -S $ServerInstance -d $env:DB_LAB_APP_DATABASE -E -C -b -f 65001 -i sql/week11/window_query.sql
sqlcmd -S $ServerInstance -d $env:DB_LAB_APP_DATABASE -E -C -b -f 65001 -i sql/week12/recursive_query.sql
sqlcmd -S $ServerInstance -d $env:DB_LAB_APP_DATABASE -E -C -b -f 65001 -i sql/week12/test_transactions.sql
sqlcmd -S $ServerInstance -d $env:DB_LAB_APP_DATABASE -E -C -b -f 65001 -i sql/week12/test_category_maintenance.sql
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

要展示第10周 Web 销售统计、补货建议及库存校正，以及第12周的订单完成和补货入库，可在同一环境启动：

```powershell
.\.venv\Scripts\python.exe -m webapp
```

浏览器访问 <http://127.0.0.1:5050/>。结束后在运行 Web 的终端按 Ctrl+C，按文末“每次复现后的清理”删除本批次数据库及备份。浏览器自动验收和 ER 图重绘的可选环境依赖为 `requirements-qa.txt`。

## 第三阶段目录

```text
sql/week10/、sql/week11/、sql/week12/   本阶段程序对象及测试
report/week10_report.md、week11_report.md、week12_report.md   本阶段报告
plan/week10-procedures-functions-plan.md  第10周实施计划
docs/ai_usage_log.md、docs/ai使用文档.md   第三阶段AI辅助记录
docs/team_division.md                     第三阶段分工
result/week10/、result/week11/、result/week12/   本阶段验收证据
webapp/、tools/、tests/                  网站、建库、验证与清理工具
sql/v01/、sql/v10/、sql/v11/、sql/app/    运行所需既有数据库对象
archive/                                 旧阶段的报告、分工、计划和记录
```

## 每次复现后的清理（按 RunId）

按第1至第4步依次操作。第3步的路径A与路径B二选一，完成所选路径后进入第4步。需要清理中断批次或同时撤销受限运行账户时，先阅读后面的特殊情况，再执行第3步。

**一次从空库复现会创建三个数据库。** 两次复现使用两个RunId，会产生两组、共六个数据库；清理时每个RunId分别执行一遍本流程。

每次执行 tools/app_prepare.py --suffix Web... 时使用一个从未使用过的后缀；这个后缀就是本次复现的 **RunId**。例如 WebNewRun01。不要复用旧后缀。

该流程会为一个 RunId 创建：

- SQL Server 数据库：TokenHubDB_v01_<RunId>、TokenHubDB_v10_<RunId>、TokenHubDB_v11_<RunId>。
- SQL 备份：v0.1→v1.0、v1.0→v1.1 两份 `.bak`，统一放在 `result/sql_backups/<RunId>/`。构建脚本查询当前 SQL Server 服务账户，并用 `icacls` 只向该账户授予此批次目录的 Modify 权限；当前项目用户保留目录管理权限。确切备份路径在执行 BACKUP 前写入 `result/week6/v11/<RunId>/copy_*.backup_path.txt`，即使备份或还原中断也能定位部分文件。
- 本次证据目录：result/source_<RunId>/、result/week6/v11/<RunId>/、result/webapp/<RunId>/。
- 可再生成的 Python/Ruff 测试缓存。

| 生成物 | 完整批次清理的处理 |
|---|---|
| v0.1、v1.0、v1.1三个数据库及其MDF/LDF | 按精确库名删除，文件由SQL Server释放 |
| Web账户、会话、订单、余额、调用、补货、退款及近14天样例 | 在该批次数据库内，随库删除 |
| app.Dashboard等程序对象与数据库角色 | 随该批次v1.1库删除 |
| 两份备份及`result/sql_backups/<RunId>/` | 按记录路径删除，并核对目录已删除 |
| `result/source_<RunId>/`、`result/week6/v11/<RunId>/`、`result/webapp/<RunId>/` | 完整清理删除；带KeepEvidence时保留 |
| `__pycache__`、Ruff等缓存 | 脚本扫描并清理仓库内共享缓存 |
| instance中的运行配置及共享日志 | 按下面的运行账户或共享日志步骤清理 |
| .venv、源码、.git、archive与其它RunId的证据 | 作为环境与项目材料保留 |

### 1. 停止本次Web服务

先保存需要保留的截图、对象编号与日志。在终端A按Ctrl+C，等待前台Web进程退出。若本次通过普通账户计划任务启动，在有权限管理任务的PowerShell中执行下列任务命令，任务名应与配置时的账户一致。

```powershell
$RuntimeAccountName = 'TokenHubWeb'
$RuntimeTaskName = "TokenHub-$RuntimeAccountName"
Disable-ScheduledTask -TaskName $RuntimeTaskName | Out-Null
Stop-ScheduledTask -TaskName $RuntimeTaskName
```

停止后在终端B检查本次端口。下例为5050，自定义端口时同步修改。

```powershell
$WebPort = 5050
$listeners = Get-NetTCPConnection -LocalPort $WebPort -State Listen -ErrorAction SilentlyContinue
if ($listeners) {
    $listeners | Select-Object LocalPort, OwningProcess
    throw '端口仍有监听，请先核对并停止本次Web服务'
}
'本次Web端口已释放'
```

预期输出为`本次Web端口已释放`，随后进入第2步。

### 2. 指定要清理的RunId和服务器

在同一清理终端执行后续步骤。输入创建时记录的RunId，服务器填写准备时传给`app_prepare.py --server`的值。

```powershell
Set-Location 'D:\Desktop\DB\DB_lab'
$Suffix = Read-Host '输入要清理的RunId，例如WebR1113220000'
$ServerInstance = 'localhost\SQLEXPRESS'
if ($Suffix -notmatch '^Web[A-Za-z0-9]{3,12}$') { throw 'RunId格式无效' }
"本次清理RunId=$Suffix；服务器=$ServerInstance"
@("TokenHubDB_v01_$Suffix", "TokenHubDB_v10_$Suffix", "TokenHubDB_v11_$Suffix")
```

核对输出的三个库名属于本次复现。每次填写一个RunId。

### 3. 选择清理路径，先预览再删除

**路径A与路径B二选一。** 路径A完整删除本批次及证据；路径B删除数据库与备份，同时保留日志、清单和验收证据。

#### 路径A　完整删除本批次（包含证据目录）

先执行预览，核对三个数据库、备份路径与三个证据目录均对应第2步的RunId。

```powershell
$KeepEvidence = $false
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -WhatIf
if ($LASTEXITCODE -ne 0) { throw '清理预览失败，请检查错误输出' }
```

核对预览后执行删除。在确认提示中输入`Y`确认当前项，或输入`A`确认本次全部操作。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -Confirm
if ($LASTEXITCODE -ne 0) { throw '清理未完成，请检查错误输出' }
```

预期末尾输出`Cleanup verification PASS for <RunId>.`，随后直接进入第4步。

#### 路径B　删除数据库和备份，保留证据目录

先执行预览。此路径在预览和删除时均使用`-KeepEvidence`。

```powershell
$KeepEvidence = $true
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -KeepEvidence -WhatIf
if ($LASTEXITCODE -ne 0) { throw '清理预览失败，请检查错误输出' }
```

核对预览中的数据库与备份路径均对应第2步的RunId，再执行删除。在确认提示中输入`Y`确认当前项，或输入`A`确认本次全部操作。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -KeepEvidence -Confirm
if ($LASTEXITCODE -ne 0) { throw '清理未完成，请检查错误输出' }
```

预期末尾输出`Cleanup verification PASS for <RunId>.`，随后进入第4步。三个证据目录继续保存在原位置。

### 4. 核验清理结果

在完成第3步的同一终端执行下面的只读核验。`$KeepEvidence`沿用所选路径的值。路径A核对三个数据库和四个批次目录均已删除；路径B核对三个数据库与备份目录已删除。

```powershell
$remainingDatabaseCount = sqlcmd -S $ServerInstance -d master -E -C -b -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name IN(N'TokenHubDB_v01_$Suffix',N'TokenHubDB_v10_$Suffix',N'TokenHubDB_v11_$Suffix');"
if ($LASTEXITCODE -ne 0) { throw '数据库核验连接失败' }
if ([int]("$remainingDatabaseCount".Trim()) -ne 0) { throw '本批次仍有数据库' }
$runPaths = @("result/sql_backups/$Suffix")
if (-not $KeepEvidence) {
    $runPaths += @("result/source_$Suffix", "result/week6/v11/$Suffix", "result/webapp/$Suffix")
}
$remainingPaths = @($runPaths | Where-Object { Test-Path -LiteralPath $_ })
if ($remainingPaths.Count) { throw "本批次仍有待清理目录：$($remainingPaths -join ', ')" }
"清理核验通过；RunId=$Suffix；保留证据=$KeepEvidence"
```

预期输出为`清理核验通过`及本次RunId。需要清理另一批次时，从第2步重新填写那个RunId，并完成第3、4步。再次创建时生成新的RunId。

### 清理范围与特殊情况

大屏过程、近14天样例顾客/商品/订单、余额、Token批次和退款账本随该批次v1.1数据库一同清除。样例脚本不创建额外数据库或Windows账户。若还要撤销该批次专用运行账户，应在执行清理前选择后面的`-RemoveRuntime`组合命令，一次清理完成。

`-Server` 必须与准备时传给 `app_prepare.py --server` 的值一致；默认是 `localhost\SQLEXPRESS`。清理脚本核对成功运行留下的 `result/webapp/<RunId>/manifest.json`，只处理由后缀精确组成的三个数据库名，不使用 `LIKE` 或数据库通配符。新批次只检查 `result/sql_backups/<RunId>/`，不访问 SQL Server 的 `Program Files` 默认备份目录；删除数据库时 SQL Server 会一并释放对应 MDF/LDF，不要手动删除数据库文件。

对应的Git已跟踪结果文件会在工作区显示删除，应在提交前核对。批次目录外另存的截图和报告按保存位置管理。

#### 复现中断，尚未生成manifest.json

确认该后缀是本次新建且三个目标数据库属于本次复现后，在第3步所选路径的预览和删除命令中同时加入`-AllowIncomplete`。下面以保留证据为例，完成第1、2步后用本组命令执行第3步。

```powershell
$KeepEvidence = $true
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -KeepEvidence -AllowIncomplete -WhatIf
if ($LASTEXITCODE -ne 0) { throw '中断批次清理预览失败' }
```

核对预览后执行删除，成功后进入第4步。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -KeepEvidence -AllowIncomplete -Confirm
if ($LASTEXITCODE -ne 0) { throw '中断批次清理未完成' }
```

#### 同时删除受限Web运行账户

只有执行过 tools/setup_web_runtime.ps1 并且要一并撤销该次专用运行环境时才使用。先在同一终端设置`$RuntimeAccountName`为配置时的账户名，与停止任务时保持一致。必须提供当时的准确 -RuntimeAccountName；默认账户名是 TokenHubWeb。该选项会停止并删除指向本仓库 tools/run_web.ps1 的计划任务、删除对应 SQL 登录、带有 TokenHub 专用描述的本地账户及其未加载的用户配置目录，并删除 instance/runtime.json、运行日志等指定文件。它不会读取运行配置中的密钥。请确认该账户/任务没有被其它项目或复现共用，并在管理员 PowerShell 中执行：

本组命令替代第3步的普通清理命令，完成后进入第4步。下面保留批次证据；完整删除证据时，将`$KeepEvidence`设为`$false`，并从预览和删除两条命令中同时去掉`-KeepEvidence`。中断批次还需在两条命令中同时加入`-AllowIncomplete`。

```powershell
$RuntimeAccountName = 'TokenHubWeb'
$KeepEvidence = $true
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -KeepEvidence -RemoveRuntime -RuntimeAccountName $RuntimeAccountName -WhatIf
if ($LASTEXITCODE -ne 0) { throw '运行账户清理预览失败' }
```

核对预览后执行删除。账户配置目录已加载时，先注销该账户或重启电脑，再重试。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -KeepEvidence -RemoveRuntime -RuntimeAccountName $RuntimeAccountName -Confirm
if ($LASTEXITCODE -ne 0) { throw '运行账户清理未完成' }
```

如果没有配置受限运行账户，不要加 `-RemoveRuntime`；开发预览的环境变量随终端关闭，不需要额外清理。**旧批次兼容**：在此备份目录改造前创建的批次（包括早期 `WebNewRun01`）把 `.bak` 放在 SQL Server 的默认 `Program Files` 目录。若当前账户无权访问，脚本会在任何删除动作前中止；只需对这种旧批次在具有对应 NTFS 权限的提升 PowerShell 中执行同一条清理命令。新批次的备份隔离在仓库内，不需要管理员权限清理。

清理结束核对脚本末尾的验证结果。中途失败示例带有`-KeepEvidence`，需要连同该批次证据一并删除时，将`$KeepEvidence`设为`$false`并从两条命令中同时去掉该参数。

### 可选　清理共享日志和当前终端变量

前台预览也会产生共享运行日志。服务停止后，如本机运行记录无需保留，可单独清除以下文件；这些日志可能包含多个批次。

```powershell
$sharedLogs = @('instance/webapp.log', 'instance/webapp.log.1', 'instance/webapp.log.2', 'instance/webapp.log.3')
foreach ($logPath in $sharedLogs) {
    if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        Remove-Item -LiteralPath $logPath -Force
    }
}
```

前台预览终端可清除本次环境变量。

```powershell
Remove-Item Env:DB_LAB_DEMO_PASSWORD, Env:DB_LAB_SECRET, Env:DB_LAB_PREVIEW, Env:DB_LAB_APP_DATABASE, Env:DB_LAB_SERVER, Env:DB_LAB_PORT -ErrorAction SilentlyContinue
```

清理程序位置：`tools/cleanup_reproduction.ps1`。它会在末尾核对三个数据库、备份文件、`result/sql_backups/<RunId>/` 和证据目录是否按选项清除。`.venv/`、`.git/`、SQL 源文件、`archive/`、其它 RunId 的数据库/结果、历史验收证据均保留；Python 临时 SQL 文件夹由 `TemporaryDirectory` 自动清理。

清理脚本只处理命令中指定的 -Suffix 对应的三个数据库、该批次备份和三个证据子目录，不使用 LIKE 或通配符，也不会触及其它 RunId。旧项目测试数据库已按名单清理；archive/、本阶段结果、.venv/ 和 .git/ 均保留；未使用`-RemoveRuntime`时保留instance/。result/webapp/、result/week6/ 等父目录保留，只清理指定 RunId 子目录。SQL 备份只处理该批次记录的精确路径，不扫描或删除其它批次备份。
