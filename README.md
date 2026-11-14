# TokenHub：数据库课程项目（第 1—9 周完成，第 10—13 周进行中）

本仓库已完成**第 5—9 周的数据库重构与 Web 应用**，现进入第 10—13 周数据库编程与事务处理阶段。课程提交版本称为 **v1.0**；其中 v1.0 完成规范化迁移，内部 v1.1 继续完善库存、订单、Token 批次及退款业务。Web 页面运行在 v1.1 上。原第 1—4 周资料已统一归档至 [archive](archive/README.md)，保留作为 v0.1 迁移基线的正式 SQL 和数据库准备工具。

## 交付内容与入口

| 周次 | 当前成果 | 主要文件 |
|---|---|---|
| 第 5 周 | ER 图、实体及联系、主外键、候选码、旧结构问题 | [ER 图及设计说明](archive/coursework/week5/README.md) |
| 第 6 周 | 函数依赖、范式分析、无损分解、迁移与回归、v1.1 规则完善 | [依赖分析](archive/coursework/week6/dependency_normalization.md)、[重构方案](archive/coursework/week6/redesign_decisions.md)、[迁移](sql/v10/migration.sql)、[回归](sql/v10/regression.sql)、[第六周说明](archive/coursework/week6/README.md) |
| 第 7—9 周 | Flask 四层 Web、顾客注册和登录、商品/订单/库存/补货/退款、角色及异常控制 | [Web 操作手册](docs/webapp.md)、[应用代码](webapp/)、[Web SQL](sql/app/) |
| 第二阶段展示版 | 员工端运营概览：订单统计、14天趋势、状态分布、库存预警；SQL 实时汇总，每15秒刷新 | [看板功能与部署说明](docs/stage2_dashboard.md)、[统计过程](sql/app/dashboard.sql) |
| 最终报告 | 设计、实验过程、图示、实际运行与异常证据、总结 | **[第二阶段报告](report/stage2_report.md)** |
| 过程材料 | AI 使用记录、组内分工、复现说明 | [AI 使用文档](docs/ai使用文档.md)、[详细日志](docs/ai_usage_log.md)、[组内分工](docs/team_division.md) |

## 系统架构

```text
HTML / CSS / JavaScript（webapp/templates、webapp/static）
  ↓ /api/v1/* HTTP + CSRF
Flask 路由和统一错误处理（webapp/__init__.py）
  ↓
业务层：身份、权限、输入规则（webapp/services.py）
  ↓
数据访问层：pyodbc 参数化、事务及回滚（webapp/dao.py）
  ↓
SQL Server（sql/v01、sql/v10、sql/v11、sql/app）
```

[应用 ER 图](report/er_diagram_app.png) · [可编辑 ER 源码](report/er_diagram_app.mmd) · [模块结构图](report/overview_modules.png) · [模块可编辑源码](report/overview_modules.mmd) · [数据字典](docs/app_data_dictionary.md)。

顾客可注册、创建订单、模拟支付、查询余额、模拟 Token 消费、申请部分退款；店员查询订单/库存、受控补货及取消待支付单；管理员另可维护商品/上游账号、处理符合规则的删除及模拟退款结算，并从新增的员工管理页面创建、修改、重置密码、停用和启用普通店员；停用代替物理删除，历史流水保留。**页面“待处理（pending）”表示等待顾客支付，不是等待店员审核。** 真实支付、真实 API 计费和真实资金结算不在本演示范围。

## 环境及从空库复现

Windows 64 位、Python ≥3.11、SQL Server Express（默认 `localhost\SQLEXPRESS`）、ODBC Driver 18、`sqlcmd`、PowerShell 5.1+。建库用户必须具备 SQL Server 创建、备份和还原实验库的权限；本地网站预览仅监听 127.0.0.1。

### 路径A：新批次从空库构建（完成后跳到启动检查）

**路径A与路径B二选一。** 首次建库或创建新批次选择A；继续使用已有Web库且需要补装大屏时选择B。A成功后直接执行“启动前核对数据库”，保留A中的目标库变量。

在当前`demonstration`版本的项目根目录执行。每次准备记录同一组服务器、RunId和目标库，后续启动及清理沿用这些值。

```powershell
Set-Location 'D:\Desktop\DB\DB_lab'
$ServerInstance = 'localhost\SQLEXPRESS'
$Suffix = 'WebR' + (Get-Date -Format 'MMddHHmmss')
$DatabaseName = "TokenHubDB_v11_$Suffix"
"本次RunId=$Suffix；目标库=$DatabaseName；服务器=$ServerInstance"

if (-not (Test-Path -LiteralPath '.venv\Scripts\python.exe' -PathType Leaf)) {
    python -m venv .venv
    if ($LASTEXITCODE -ne 0) { throw '虚拟环境创建失败，请检查Python和目录权限' }
}
.\.venv\Scripts\python.exe -c "import sys; assert sys.prefix != sys.base_prefix; print('venv OK')"
if ($LASTEXITCODE -ne 0) { throw '现有虚拟环境不可用，请先检查环境' }
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) { throw '依赖安装失败' }
$env:PATH = "$pwd\.venv\Scripts;$env:PATH"
$env:DB_LAB_DEMO_PASSWORD = Read-Host '设置12至72字节的实验密码'
.\.venv\Scripts\python.exe tools/app_prepare.py --server $ServerInstance --suffix $Suffix
if ($LASTEXITCODE -ne 0) { throw '数据库准备失败，请先检查本次日志' }
```

已有可用`.venv`会直接复用。Windows覆盖正在使用的python.exe可能报Permission denied，先检查现有环境，避免反复创建。

准备程序依次执行v0.1建库、备份/还原、v1.0迁移、v1.1扩展、Web过程、`app.Dashboard`统计过程及样例账户创建。当前版本的新库自动安装大屏，安装结果记录在`result/webapp/<RunId>/04_dashboard_install.log`。数据库或结果目录重名时拒绝覆盖。

### 路径B：已有Web库补装大屏（选择路径A时跳过本节）

仅在继续使用已有Web库时执行本节。目标库必须是本机仍存在、已安装Web应用的数据库，按原RunId或启动配置填写。

```powershell
Set-Location 'D:\Desktop\DB\DB_lab'
$ServerInstance = 'localhost\SQLEXPRESS'
$DatabaseName = Read-Host '输入现有Web数据库完整名称（须与启动配置一致）'
sqlcmd -S $ServerInstance -d $DatabaseName -E -C -b -f 65001 -i sql/app/dashboard.sql
if ($LASTEXITCODE -ne 0) { throw '大屏扩展安装失败，请检查SQL输出' }
```

该增量使用`CREATE OR ALTER`安装统计过程并授予`app_runtime`执行权限，保留业务数据。只补装该过程时，沿用原数据库的RunId。代码更新后重启Web服务；仅补装SQL时可直接点击“立即刷新”。

### 2. 启动前核对数据库（A或B完成后继续）

保留所选路径设置的`$ServerInstance`和`$DatabaseName`，在同一PowerShell执行以下检查，正常时输出实际库名及`app.Dashboard`。连接失败时先核对目标库存在性与访问权限；SQL错误2812表示调用的过程缺失。

```powershell
sqlcmd -S $ServerInstance -d $DatabaseName -E -C -b -Q "IF OBJECT_ID(N'app.Dashboard',N'P') IS NULL THROW 55004,'app.Dashboard is missing',1; SELECT DB_NAME() AS database_name, N'app.Dashboard' AS installed_procedure;"
if ($LASTEXITCODE -ne 0) { throw '目标库连接或大屏对象检查失败，请核对上方SQL输出' }
```

### 3. 启动与页面核验

在终端A设置刚才核对的服务器和目标库后，前台启动。运行普通账户计划任务时，连接配置来自`instance/runtime.json`，应核对其中的server/database与安装目标一致。

```powershell
.\.venv\Scripts\python.exe tools/seed_dashboard_recent.py --server $ServerInstance --database $DatabaseName
if ($LASTEXITCODE -ne 0) { throw '近14天样例准备失败，请检查输出' }

$env:DB_LAB_SERVER = $ServerInstance
$env:DB_LAB_APP_DATABASE = $DatabaseName
$env:DB_LAB_PORT = '5050'
$env:DB_LAB_SECRET = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
$env:DB_LAB_PREVIEW = '1'
Remove-Item Env:DB_LAB_HTTPS -ErrorAction SilentlyContinue
.\.venv\Scripts\python.exe -m webapp
```

启动前的样例脚本以数据库准备身份运行，生成专用顾客`dashboard_recent_sample`与商品`Dashboard Recent Sample`，近14天每天1—4笔订单，包含待支付、支付、取消和退款。专用顾客使用随机不可知密码，日常登录继续使用原有账户。支付与退款调用已有过程，订单创建时间覆盖历史日期，支付与退款时间为本次执行时间。

同日重复执行新增数为0，后续日期启动时只补缺少的样例订单。准备过程在一个事务内完成；原订单日期保持原值。样例会计入大屏指标，识别时按专用顾客和商品筛选。运行普通账户计划任务前，也先用数据库准备身份执行这一步。

浏览器访问 **http://127.0.0.1:5050/**。顾客账户为`web_customer`、`web_other`，员工入口为`web_staff`、`web_admin`，密码取该数据库准备时设置的值。顾客也可自行注册。

在终端B确认首页响应，再由店员或管理员登录“运营概览”，核对6张指标卡、14天趋势、状态图及刷新时间，每15秒自动更新。无近期订单时趋势可以全为0；出现“刷新失败”及请求编号时，按该编号检查`instance/webapp.log`。未登录访问`/api/v1/dashboard`返回401。

```powershell
$homeResponse = Invoke-WebRequest 'http://127.0.0.1:5050/' -UseBasicParsing
if ($homeResponse.StatusCode -ne 200) { throw '首页尚未就绪' }
```

凭据与运行配置保存在Git忽略的环境变量或`instance/`中。详细统计口径见[大屏说明](docs/stage2_dashboard.md)。

正式受限 Windows 账户部署见 [Web 操作手册](docs/webapp.md) 的 `tools/setup_web_runtime.ps1`；开发预览的 `app_runtime_probe` 测试**不能替代**使用真实普通 Windows 身份的数据库权限验收。仓库须放在用户目录（`C:\Users\<用户名>`）之外，否则运行账户无法读取，配置脚本会直接拒绝。

## 目录概览

```text
sql/v01/              迁移所需原始建库及数据脚本（保留执行依赖）
sql/v10/              migration.sql、regression.sql（课程 v1.0）
sql/v11/              业务加固及退款、库存扩展
sql/app/              Web 应用过程与受限顾客注册
archive/coursework/week5/、week6/  历史 ER、范式、重构与回归资料
db_tools/v11/        当前运行依赖的 v1.1 数据库构建与验证脚本
webapp/、tools/       Web 页面/业务/DAO 与准备、验收脚本
report/               第二阶段报告、ER 图和渲染源码
docs/                 Web 操作手册、数据字典、AI 日志及分工
result/               第二阶段实际证据、迁移及测试日志
archive/              第 1—4 周旧报告、历史说明、完整原日志和旧证据
```

所有可编辑图源及 `report/render_app_er.py`、`report/render_overview_modules.py` **保留**。项目运行不依赖它们，但后续修改图像时可以重新导出；旧材料归档映射见 [archive/README.md](archive/README.md)。


## 每次复现后的完整清理（按 RunId）

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

### 先停止服务，再预览清理

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

清理目标使用准备时记录的RunId和服务器。下面是完整清理，包含本次日志与清单。核对`-WhatIf`输出后执行带确认的命令。

```powershell
Set-Location 'D:\Desktop\DB\DB_lab'
$Suffix = Read-Host '输入要清理的RunId，例如WebR1113220000'
$ServerInstance = 'localhost\SQLEXPRESS'
if ($Suffix -notmatch '^Web[A-Za-z0-9]{3,12}$') { throw 'RunId格式无效' }

powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -WhatIf
if ($LASTEXITCODE -ne 0) { throw '清理预览失败，请检查错误输出' }

powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -Confirm
if ($LASTEXITCODE -ne 0) { throw '清理未完成，请检查错误输出' }
```

大屏过程、近14天样例顾客/商品/订单、余额、Token批次和退款账本随该批次v1.1数据库一同清除。样例脚本不创建额外数据库或Windows账户。若还要撤销该批次专用运行账户，应在执行清理前选择后面的`-RemoveRuntime`组合命令，一次清理完成。

`-Server` 必须与准备时传给 `app_prepare.py --server` 的值一致；默认是 `localhost\SQLEXPRESS`。清理脚本核对成功运行留下的 `result/webapp/<RunId>/manifest.json`，只处理由后缀精确组成的三个数据库名，不使用 `LIKE` 或数据库通配符。新批次只检查 `result/sql_backups/<RunId>/`，不访问 SQL Server 的 `Program Files` 默认备份目录；删除数据库时 SQL Server 会一并释放对应 MDF/LDF，不要手动删除数据库文件。

正常结束应输出`Cleanup verification PASS for <RunId>.`。完整清理后，在同一终端执行下面的只读核验，确认三个数据库与四个批次目录均已删除。

```powershell
$remainingDatabaseCount = sqlcmd -S $ServerInstance -d master -E -C -b -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name IN(N'TokenHubDB_v01_$Suffix',N'TokenHubDB_v10_$Suffix',N'TokenHubDB_v11_$Suffix');"
if ($LASTEXITCODE -ne 0) { throw '数据库核验连接失败' }
if ([int]("$remainingDatabaseCount".Trim()) -ne 0) { throw '本批次仍有数据库' }
$runPaths = @("result/source_$Suffix", "result/week6/v11/$Suffix", "result/webapp/$Suffix", "result/sql_backups/$Suffix")
$remainingPaths = @($runPaths | Where-Object { Test-Path -LiteralPath $_ })
if ($remainingPaths.Count) { throw "本批次仍有目录：$($remainingPaths -join ', ')" }
'完整批次清理已核验'
```

对应的Git已跟踪结果文件会在工作区显示删除，应在提交前核对。批次目录外另存的截图和报告按保存位置管理。

**需要保留证据时改用以下一组命令**。此模式有意保留三个结果目录，只检查数据库与备份目录已删除。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -KeepEvidence -WhatIf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -KeepEvidence -Confirm
```


如果复现中途失败，尚未生成 manifest.json，清理程序默认拒绝猜测。确认该后缀是本次新建且三个目标数据库确实属于本次复现后，才加 -AllowIncomplete：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -KeepEvidence -AllowIncomplete -WhatIf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -KeepEvidence -AllowIncomplete -Confirm
```

### 可选：同时删除受限 Web 运行账户

只有执行过 tools/setup_web_runtime.ps1 并且要一并撤销该次专用运行环境时才使用。先在同一终端设置`$RuntimeAccountName`为配置时的账户名，与停止任务时保持一致。必须提供当时的准确 -RuntimeAccountName；默认账户名是 TokenHubWeb。该选项会停止并删除指向本仓库 tools/run_web.ps1 的计划任务、删除对应 SQL 登录、带有 TokenHub 专用描述的本地账户及其未加载的用户配置目录，并删除 instance/runtime.json、运行日志等指定文件。它不会读取运行配置中的密钥。请确认该账户/任务没有被其它项目或复现共用，并在管理员 PowerShell 中执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -KeepEvidence -RemoveRuntime -RuntimeAccountName $RuntimeAccountName -WhatIf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cleanup_reproduction.ps1 `
  -Suffix $Suffix -Server $ServerInstance -KeepEvidence -RemoveRuntime -RuntimeAccountName $RuntimeAccountName -Confirm
```

如果没有配置受限运行账户，不要加 `-RemoveRuntime`；开发预览的环境变量随终端关闭，不需要额外清理。**旧批次兼容**：在此备份目录改造前创建的批次（包括早期 `WebNewRun01`）把 `.bak` 放在 SQL Server 的默认 `Program Files` 目录。若当前账户无权访问，脚本会在任何删除动作前中止；只需对这种旧批次在具有对应 NTFS 权限的提升 PowerShell 中执行同一条清理命令。新批次的备份隔离在仓库内，不需要管理员权限清理。

清理结束核对脚本末尾的验证结果。中途失败与运行账户示例带有`-KeepEvidence`，需要连同该批次证据一并删除时，两条命令均去掉该参数。

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

清理脚本只处理命令中指定的 -Suffix 对应的三个数据库、该批次备份和三个证据子目录，不使用 LIKE 或通配符，也不会触及其它 RunId。2026-11-14已按用户要求清理本机全部36个TokenHubDB项目库，之后按路径A重新建立新批次；迁移前 ZIP、archive/、result/stage2/、.venv/ 和 .git/ 均保留；未使用`-RemoveRuntime`时保留instance/。result/webapp/、result/week6/ 等父目录保留，只清理指定 RunId 子目录。SQL 备份只处理该批次记录的精确路径，不扫描或删除其它批次备份。

## 第9周员工管理增补（2026-11-04）

店长（管理员）登录后在左侧选择“员工管理”，可以查看普通店员、新增店员、修改姓名、重置密码、停用或重新启用；没有物理删除按钮，原因是员工与补货/库存操作的历史外键应保留。店员不能通过管理页面创建管理员或管理其他员工；停用和密码重置均会撤销旧会话。

第9周新建隔离数据库 WebEmp26A01 的最新验证：[正常与异常截图索引](result/stage2/WebEmp26A01/README.md)，包含重新截图22张原有业务画面和新增11张员工管理画面、25项SQL对账。原有 WebStage2A02 证据保留供审计。陈诗翰负责第9周追加测试及更新，阮依成负责新增员工管理和本轮测试/截图/文档整理。

**已有 Web 实验数据库更新时不需要重建旧库**：在具备数据库安装权限的 PowerShell、项目根目录执行下方 SQLCMD，然后重启 Flask 以加载新路由；务必核对目标库名，不对原始旧库执行。

    sqlcmd -S 'localhost\SQLEXPRESS' -d TokenHubDB_v11_WebYourRun01 -E -C -b -f 65001 -v DatabaseName=TokenHubDB_v11_WebYourRun01 -i sql/app/employees.sql

全新使用 app_prepare.py 构建的 Web 后缀库则自动包含员工管理过程。
