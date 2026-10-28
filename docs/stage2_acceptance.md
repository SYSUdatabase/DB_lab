# 第二阶段：全角色人工验收清单（供补充复现和异常测试）

按“启动服务器 → 游客 → 管理员准备 → 顾客交易 → 店员运营 → 管理员收尾 → 关闭服务器”的顺序操作。每一步都列出预期结果；结果不符时记录订单/账号/任务编号和页面请求编号，不把下列预期直接登记成已通过。运行配置见[应用手册](webapp.md)，此前自动测试结果见[证据索引](../result/webapp/README.md)。

### 0. 准备环境和记录表

#### 0.1 启动前检查

打开 PowerShell，进入**原项目目录**。以下命令仅检查，不创建数据库、不修改样例数据：

```powershell
Set-Location -LiteralPath 'D:\Desktop\DB\DB_lab'
if (-not (Test-Path -LiteralPath '.venv\Scripts\python.exe')) {
    throw '缺少项目虚拟环境，请先按上方运行说明安装环境和 requirements.txt'
}
& .\.venv\Scripts\python.exe -c "import flask, pyodbc, bcrypt, waitress; print('Web依赖可用')"
if ($LASTEXITCODE -ne 0) { throw '缺少Web依赖，请先安装 requirements.txt' }
Get-Service -Name 'MSSQL$SQLEXPRESS'
Get-NetTCPConnection -LocalPort 5050 -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, OwningProcess
```

SQL Server 服务应为 `Running`。若未运行，由有权限的人员启动对应实例；自定义实例名称按实际配置替换。5050端口有监听时，先确认是否为本项目已经运行的服务器，不要再启动第二份，也不要按“所有Python进程”批量结束程序。原来的前台服务器应回原终端按 `Ctrl+C`；计划任务服务器按第9.2节关闭，然后继续。

首次验收尚未准备数据库时，先按上方建库说明或[应用手册](webapp.md)完成准备。`app_prepare.py` 是一次性建库入口，**不是每次启动服务器的命令**；每次验收都重建库会改变样例和编号。

#### 0.2 方式一 前台启动开发预览

没有配置专用 Windows 运行账户时，先用此方式检验页面及业务。保留这个 PowerShell 窗口，称为“终端A”，验收完成后在同一窗口停止服务器。预览使用数据库受限用户，不替代专用 Windows 账户的权限验收。

```powershell
Set-Location -LiteralPath 'D:\Desktop\DB\DB_lab'
$env:DB_LAB_SERVER = 'localhost\SQLEXPRESS'
# 本机已有库的启动示例；检验下文精确数值时，换成自己准备的干净应用库名。
$env:DB_LAB_APP_DATABASE = 'TokenHubDB_v11_Web261021D'
$env:DB_LAB_PORT = '5050'
$env:DB_LAB_PREVIEW = '1'
$env:DB_LAB_SECRET = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
Remove-Item Env:DB_LAB_HTTPS -ErrorAction SilentlyContinue

# 使用现有 Windows 身份只读检查指定库及应用入口是否存在。
& sqlcmd -S $env:DB_LAB_SERVER -d $env:DB_LAB_APP_DATABASE -E -C -b `
    -Q "SET NOCOUNT ON; IF OBJECT_ID(N'app.Execute', N'P') IS NULL THROW 55000, 'Application schema missing', 1; SELECT DB_NAME() AS application_database;"
if ($LASTEXITCODE -ne 0) { throw '数据库或应用结构未准备好，请先检查配置，暂不启动服务器' }

# 保持前台运行；没有持续输出也可能是正常状态，按下一节检查是否已就绪。
& .\.venv\Scripts\python.exe -m webapp
```

启动后终端A暂时不返回命令提示符是正常现象，不要把这一状态当成程序卡住，也不要继续在终端A粘贴其他验收命令。另开“终端B”执行第0.4节。启动失败会返回终端并显示错误；常见原因是实例/库名不符、依赖缺失或端口被占用，修正后重新启动。每次生成新的运行密钥会使旧浏览器登录失效，重新登录即可；不要把运行密钥复制到验收记录。

#### 0.3 方式二 启动已配置的普通账户计划任务

**与方式一二选一，不能同时占用5050端口。** 已按应用手册运行过 `setup_web_runtime.ps1`、专用账户及计划任务均已配置时，才使用此方式。不要为了日常启动反复执行账户安装脚本。

在有权限管理该任务的 PowerShell 中执行；以下按默认账户 `TokenHubWeb`、默认端口5050举例，自定义账户时任务名为 `TokenHub-<账户名>`：

```powershell
Set-Location -LiteralPath 'D:\Desktop\DB\DB_lab'
$taskName = 'TokenHub-TokenHubWeb'
Get-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null
Enable-ScheduledTask -TaskName $taskName | Out-Null
Start-ScheduledTask -TaskName $taskName
Get-ScheduledTask -TaskName $taskName | Select-Object TaskName, State
```

该方式按本地 `instance/runtime.json` 的配置运行，不能通过设置当前终端的 `DB_LAB_APP_DATABASE` 改变任务使用的数据库。任务启动时先以其 Windows 身份运行权限检查，再启动Web服务。接着执行第0.4节；未就绪时检查本地 `instance/runtime_identity.log` 和 `instance/runtime.log`，不要直接显示或提交包含密钥的运行配置。单独在当前管理员身份下执行 `run_web.ps1` 不等于以普通账户运行计划任务。

#### 0.4 确认服务器就绪

在另一个 PowerShell（终端B）执行。默认地址如下；自定义了端口时同时替换URL和后续端口检查中的数字。

```powershell
$baseUrl = 'http://127.0.0.1:5050'
$homeResponse = Invoke-WebRequest -Uri "$baseUrl/" -UseBasicParsing -TimeoutSec 10
if ($homeResponse.StatusCode -ne 200) { throw '首页尚未就绪' }
$catalog = Invoke-RestMethod -Uri "$baseUrl/api/v1/products" -TimeoutSec 10
if ($catalog.code -ne 'OK') { throw '商品接口尚未就绪，请检查数据库连接和运行身份' }
'首页与商品查询已就绪，可以开始人工验收'
```

首页与商品接口均成功后，再在浏览器打开 [TokenHub](http://127.0.0.1:5050/)，执行下列角色操作。首页能打开而商品查询失败时，不能视为服务已可验收。

#### 0.5 记录本轮环境与账户

1. 打开 [TokenHub](http://127.0.0.1:5050/)。页面已经登录时先点“退出登录”。
2. 为获得下文的确定数值，使用按应用手册创建的**全新实验库**；`web_customer` 的 `Other` 余额应为零，且没有该 provider 尚未消费的历史购买批次。已有数据不满足时另用新后缀准备库，不删除旧库或清空历史记录。仅换商品名称不能隔离同 provider 的 FIFO 批次。
3. 用本次建库时设置的样例密码登录。现有本机环境的密码由持有人在本地 `instance/demo_password.txt` 查看，不写入本文件、截图或提交。下列演示账户由准备工具创建；新顾客也可通过登录弹窗内的注册入口自行注册。
4. 每次换身份都先退出，再选择正确的“登录入口”；不要在共享 Cookie 的两个标签页中同时扮演不同身份。需要并排比较时使用不同浏览器配置或无痕窗口。
5. 给验收对象名称附加本轮后缀，例如 `1021A`。下文用 `P/Q/R` 代表商品、`A/B` 代表上游账号、`O1～O6` 代表实际返回的订单编号、`T1/T2` 代表补货任务；它们不是数据库中的固定编号。商品编号可从顾客选择套餐下拉框或接口结果核对。

| 身份 | 登录入口 | 账户 | 需要覆盖的职责 |
|---|---|---|---|
| 游客 | 不登录 | — | 在售目录、搜索、分页、进入登录；不能访问受限业务 |
| 顾客 | 顾客登录 | `web_customer` | 本人订单和明细、取消草稿、模拟支付、余额、调用、退款及记录查询 |
| 第二位顾客 | 顾客登录 | `web_other` | 本人数据隔离，不能访问或操作第一位顾客的订单 |
| 店员 | 员工登录 | `web_staff` | 商品只读、全体订单/余额/调用/退款查询、取消待支付单、库存和补货 |
| 管理员 | 员工登录 | `web_admin` | 店员全部职责，加商品维护、账号维护、必要删除和模拟退款结算 |

页面每页20条；对象不在当前页时翻页，商品和订单还可使用搜索。查询和提交后等待列表或成功提示更新，再继续下一步。支付、API 调用、退款结算均为本地模拟。

建议按下表记录，失败时补充页面提示和请求编号；本流程编写完成不等于已经由组员人工执行。

| 检验人 / 日期 | 应用数据库 / Git 提交 | 步骤编号 | 对象实际编号 | 操作前值 → 操作后值 | 通过 / 失败 | 截图或请求编号 |
|---|---|---|---|---|---|---|
| 待填写 | 待填写 | 待填写 | 待填写 | 待填写 | 待填写 | 待填写 |

### 1. 游客、注册与登录

| 编号 | 人工操作 | 预期结果 |
|---|---|---|
| G1 | 未登录打开首页，浏览“商品目录”；搜索 `OpenAI`，再搜索不存在的名称，最后清空搜索。 | 只展示在售商品；筛选结果和总数更新；无匹配时显示空状态，清空后恢复。没有库存、余额或订单导航。 |
| G2 | 核对“上一页/下一页”和记录总数。 | 第一页“上一页”禁用，最后一页“下一页”禁用；超过20条时可翻页，无重复漏页的异常表现。样例不足21条时记录“翻页成功路径未检验”，不要写已通过。 |
| G2a | 在登录弹窗点“还没有账号？注册顾客账户”，填写新用户名、邮箱和两次相同的密码，提交后退出再登录。然后重复注册同一用户名或邮箱。 | 注册成功即自动以普通顾客登录；退出后能用新密码登录；重复注册返回409。员工和管理员不允许自助注册。 |
| G3 | 点击“登录购买”，先填错误密码，再用 `web_customer` 和正确密码登录。 | 错误密码得到简明提示；正确登录后右上角为“顾客 · 已登录”，出现订单、余额、调用、退款导航。密码不出现在页面提示中。 |
| G4 | 退出登录，再按第7节的方法调用 `checkApi('/orders')`。 | 恢复游客目录，订单请求返回 HTTP 401；不能借退出前页面继续访问本人记录。 |

### 2. 管理员准备商品与上游账号

以 `web_admin` 从“员工登录”进入。这里只准备数据，后续再检验管理员收尾职责。

| 编号 | 人工操作 | 预期结果 |
|---|---|---|
| A1 | “商品目录 → 新增商品”，创建下表的 P、Q、R，状态均选“在售”。 | 三笔新增成功，列表显示名称、供应商、Token档位和价格。记录实际商品编号。 |
| A2 | 编辑 R：价格由 `0.50` 改为 `0.75`，修改描述，依次切换“下架”“停售”，最后恢复“在售”。 | 编辑后重新打开能看到保存值；退出为游客时，下架/停售的 R 不出现，在售时出现；管理员能查询各状态商品。价格小于1元仍可提交。 |
| A3 | 删除从未被使用的 R，并确认。 | 删除成功，再搜索名称没有记录。P、Q 保留供后续订单使用。 |
| A4 | 再次新增一个 `Other + 100000 Token` 商品；另试价格 `0`、负数数量或遗漏名称。 | 重复供应商/档位被约束拒绝；非法字段由表单或后端拒绝，不新增半条数据，页面不泄露 SQL。 |
| A5 | “上游库存 → 新增上游账号”，创建 A、B：供应商 `Other`，初始总额度 `1000000`，安全阈值 `10000`，状态 `active`；到期时间留空或选未来。 | 每个新账号各出现一条库存记录，可用额度均为 `1000000`，无需另建库存。记录 A、B 编号。 |
| A6 | 编辑 B：修改名称、安全阈值为 `20000`，先暂停再恢复有效，保存后重新打开核对。 | 元数据修改生效，额度仍为 `1000000`；编辑页面没有直接覆盖总额度/已用额度的入口。 |
| A7 | 删除只有系统期初流水、尚无调用和补货等业务引用的 B。 | 账号、配对库存及其期初流水一起删除；列表不残留孤立库存。A 保留用于补货。 |

| 代号 | 套餐名称示例 | 供应商 | 单价 | 套餐 Token | 每套餐上游消耗 |
|---|---|---|---:|---:|---:|
| P | `人工验收P-1021A` | Other | 12.00 | 100000 | 100000 |
| Q | `人工验收Q-1021A` | Other | 20.00 | 200000 | 200000 |
| R | `人工验收R-1021A` | Other | 0.50 | 300000 | 300000 |

同一供应商与Token档位组合唯一；若这些档位已存在，说明不是本流程假定的全新环境，先核对准备步骤，不覆盖原商品。顾客支付不会扣库存，实际模拟调用才会扣减。服务端会选择符合条件且编号最小的上游账号，**不保证调用使用新建的 A**。

### 3. 顾客订单与明细

退出管理员，使用 `web_customer` 登录。先查看“Token 余额”，确认 Other 无余额行或为0；记录其它 provider 的原值。

| 编号 | 人工操作 | 预期结果 |
|---|---|---|
| C1 | “创建订单”：P 数量1加入明细，再把 P 数量1加入一次，再加入 Q 数量1，提交并记为 O1。 | 状态为“待处理”（pending）；O1“详情”仅两条商品明细，P 数量2、Q 数量1；金额 `44.00`，Token `400000`。说明同商品在数据库中合并数量。 |
| C2 | O1“详情”中将 P 数量改为3，点“更新数量”。 | P 小计 `36.00`；订单金额 `56.00`，Token `500000`。关闭再打开详情，值一致。 |
| C3 | 删除 O1 的 Q 明细。 | 只剩 P，订单金额 `36.00`、Token `300000`。 |
| C4 | O1“详情 → 增加一项商品”，重新加入 Q 数量1，提交后重开详情。 | 恢复两项明细；金额 `56.00`、Token `500000`。 |
| C5 | 再删除 Q，将 P 更新为数量1。 | O1 最终仅 P，单价快照 `12.00`，金额 `12.00`、Token `100000`；尚未支付，余额不变。 |
| C6 | 暂时退出，以管理员把 P 当前价格改为 `15.00`；再以原顾客登录，打开 O1。 | 目录显示 `15.00`，O1 原明细仍为 `12.00`；不按新价格重算历史快照。 |
| C7 | O1“增加一项商品”，再加入 P 数量1。 | 仍是一条 P 明细，数量2；沿用首次快照价 `12.00`，订单金额 `24.00`、Token `200000`。 |
| C8 | 新建 O4，仅选 P 数量1；提交后在详情中删除唯一明细，再尝试“模拟支付”。 | O4 金额、Token均为0，明细为空；支付被拒绝，仍为 pending，余额不变。保留 O4 给店员取消、管理员删除。 |
| C9 | 新建含 P 的 O5，点“取消”并确认。 | O5 状态为“已取消”，明细仍保留；没有余额入账或库存扣减。 |
| C10 | 再新建含 P 的 O6，保持待支付，供管理员继承职责检查。 | 创建成功，保持 pending，不改变余额和库存。 |

订单列表可按编号搜索，详情应与列表汇总一致。后续每次查找以记录的实际编号为准，不依赖“第一行就是某笔订单”。

### 4. 顾客支付、调用和三类退款

保持 `web_customer` 身份。可先让店员按第5节记录当前 Other 账号额度，再回到顾客操作，以便比较库存变化。

| 编号 | 人工操作 | 预期结果 |
|---|---|---|
| C11 | 对 O1 点“模拟支付 → 确认提交”。 | O1 变为“已支付”，Other余额增加 `200000`；上游库存不变，其它 provider 余额不变。 |
| C12 | 查看 O1 详情；再用第7节接口方法重复支付。 | 页面不再提供可修改的明细控件；重复支付 HTTP 409，Other余额不重复增加。 |
| C13 | “调用记录 → 模拟调用”，选择 P，消费Token填 `50000`。 | 新增一条调用记录，消费 `50000`；Other余额从 `200000` 减至 `150000`。P上游折算比为1，实际被选择账号的库存减少 `50000`；详情字段可用第7节查询接口辅助核对。 |
| C14 | 再试调用 `150001` Token；另试 `0` 或负数。 | 余额不足或参数校验拒绝；余额仍 `150000`，没有新成功调用，库存不再减少。记录失败前后值。 |
| C15 | O1 点“申请退款 → 确认提交”，再查看“退款账本”。 | O1为“部分退款”；回收 `150000` Token，已消费 `50000`，应退 `18.00`（`24 × 150000 / 200000`）；Other余额为0，结算为“待模拟结算”。退款不回补已消费的上游库存。 |
| C16 | 用第7节接口方法重复请求 O1 退款，再刷新账本。 | HTTP 200，返回原订单结果；仍只有一笔该订单退款，金额与Token不重复扣减。 |
| C17 | 按 P 的新目录价创建 O2，数量1，模拟支付后立即申请退款，不进行调用。 | 成交价 `15.00`，发放并回收 `100000` Token；应退 `15.00`，O2为“已退款”，Other余额回到0。O1、O2可以同时待结算。 |
| C18 | 再创建 O3，P 数量1，支付后模拟调用 `100000` Token，再尝试退款。 | 消费后Other余额为0；退款被拒绝，O3仍为paid，无该订单的新退款账本项；已有调用保留。 |
| C19 | 分别查看本人“订单管理”“Token余额”“调用记录”“退款账本”，核对 O1～O6 和成功/失败次数。 | 查询只含本人数据；失败调用/失败退款不增加成功记录。当前这轮 Other 余额为0，成功调用共 `150000` Token，上游库存合计减少 `150000`（不计另外完成的补货）。 |
| C20 | 退出，以 `web_other` 顾客身份登录，查询上述四类记录，并尝试读取、支付或退款 O1。 | 看不到 `web_customer` 的这些记录；直接接口访问 O1被拒绝（403），不能通过修改URL操作别人的订单。 |

退款金额按明细成交小计比例逐项取到分，不按当前目录价格计算。上述绝对余额和退款金额依赖第0节的干净 Other 账本条件；若已有旧批次，FIFO会先消费旧批次，此时应先隔离验收数据，不能把期望金额硬套在旧数据上。

### 5. 店员运营职责

以 `web_staff` 从“员工登录”进入。

| 编号 | 人工操作 | 预期结果 |
|---|---|---|
| S1 | 查看“商品目录”，搜索 P；核对页面按钮。 | 能查商品，包括已下架记录；没有“新增商品”“编辑”“删除”权限入口。 |
| S2 | 查看“订单管理”，搜索 O1、O4、O5，打开详情；再查看“Token余额”“调用记录”“退款账本”。 | 能查询不同顾客及原样例的运营数据，能看到 O1/O2 的应退款项；不能替顾客模拟支付、调用或申请退款，不能修改已付明细。 |
| S3 | 在 O4 上点“取消”并确认。 | 空草稿O4从pending变为cancelled；店员没有“删除空单”能力。O5本来已取消，不再提供再次取消入口。 |
| S4 | “上游库存”中找到 A，记录额度 `1000000`；点该行“补货”，计划补货 `10000`，创建 T1。 | 任务创建成功，当前库存仍 `1000000`；创建任务本身不增加库存。 |
| S5 | “补货任务”中找到 T1，点“完成补货”，实际补货填 `8000` 并确认。 | T1为“已完成”，计划 `10000`、实际 `8000`；A库存变为 `1008000`，按实际数量增加。再次完成按钮消失，重复接口请求被拒绝且额度不再增加。 |
| S6 | 在“补货任务 → 创建补货任务”再次为 A 新建 T2，计划 `2000`，暂不完成。 | 从任务页也能创建任务；A库存仍为 `1008000`。保留 T2 给管理员完成。 |
| S7 | 用第7节方法尝试新增商品、修改/删除 A、删除 O4 或结算 O1。 | 这些直接API请求均403，不能依靠绕过隐藏按钮获得管理员能力。失败后原记录不变。 |

上游库存页是查看和受控补货入口，没有任意覆盖库存数值的操作。检查 C13/C19 的库存扣减时，根据调用记录中的 `account_id` 或 Other 所有账号总额核对；不要默认消耗发生在 A。若 Other有多页账号，合计必须包含全部页。

### 6. 管理员收尾及继承职责

退出店员，以 `web_admin` 登录。

| 编号 | 人工操作 | 预期结果 |
|---|---|---|
| A8 | 重做 S1/S2 的跨顾客查询：商品、订单详情、余额、调用、库存、补货、退款七个板块分别查看。 | 管理员能读取运营数据；此前顾客的订单快照、消费记录和应退款金额保持一致。 |
| A9 | 对仍待支付的 O6执行“取消”。 | 取消成功；证明管理员继承店员的取消职责，但不获得顾客的购买/调用身份。 |
| A10 | 在“补货任务”完成店员创建的 T2，实际填 `2000`；再由管理员自己创建并完成 A 的 T3，实际填 `1000`。 | 两次均成功，任务实际处理人取当前管理员；A库存依次为 `1010000`、`1011000`。管理员也能从库存行“补货”创建任务。 |
| A11 | 尝试删除已经有补货引用的 A，再尝试删除已经有订单引用的 P。 | 两者均被拒绝；A、P及原有订单/补货数据保留。P可下架，不能以物理删除破坏历史。 |
| A12 | 对空且已取消的 O4 点“删除空单”；再尝试删除仍保留明细的 O5。 | O4删除成功；O5因非空被拒绝。已支付/已退款订单不允许删除，可用第7节直接接口补验。 |
| A13 | “退款账本”分别对 O1、O2 点“模拟结算 → 确认提交”。 | 两笔从“待模拟结算”变为“模拟结算完成”；仍分别为 `18.00` 和 `15.00`，不再扣顾客Token。 |
| A14 | 用第7节方法重复结算 O1，并查询退款账本结果。 | 返回原结果，不产生第二笔退款；后端保存服务端生成的 `SIM-<订单编号>`。界面输入的编号不改变这一服务端规则。 |
| A15 | 将 P、Q 下架；退出为游客，再搜索名称，随后管理员登录恢复在售。 | 游客看不到下架商品；管理员仍可查询和恢复；历史订单详情与金额不变。 |

“模拟结算完成”只表示本地账本登记，不代表外部支付渠道已向顾客转账。保留本轮订单、调用、退款及补货记录，不通过清库伪造恢复初始状态。

### 7. 手动检查隐藏按钮后的接口权限

在应用页面打开浏览器开发者工具的 Console，输入下列函数。它只使用当前浏览器登录会话和CSRF，不要在控制台打印Cookie、密码或会话令牌。

```javascript
async function checkApi(path, method = 'GET', payload = {}) {
  const session = await fetch('/api/v1/auth/session').then(r => r.json());
  if (session.code !== 'OK') throw new Error(session.message);
  const options = {
    method,
    headers: {'Content-Type': 'application/json', 'X-CSRF-Token': session.data.csrf}
  };
  if (method !== 'GET') options.body = JSON.stringify(payload);
  const response = await fetch('/api/v1' + path, options);
  const body = await response.json();
  console.table([{
    status: response.status, code: body.code,
    message: body.message, request_id: body.request_id
  }]);
  return body.data;
}
```

下表中的 `<O1>`、`<O4>`、`<A>`、`<P>` 必须替换为本轮记录的数字，不能原样粘贴。只在对应步骤之后执行成功/重复请求，避免提前改变后续状态。

| 身份与时点 | 控制台示例 | 预期 |
|---|---|---|
| 游客 | `await checkApi('/orders')` | 401，未登录 |
| 顾客 | `await checkApi('/inventory')` | 403，无库存权限 |
| web_other | `await checkApi('/orders/<O1>')` | 403，不能查看其他顾客订单 |
| web_other | `await checkApi('/orders/<O1>/pay', 'POST')` | 403，不改变O1 |
| web_other | `await checkApi('/orders/<O1>/refund', 'POST')` | 403，不增加退款记录 |
| 顾客，C11后 | `await checkApi('/orders/<O1>/pay', 'POST')` | 409，不能重复充值 |
| 顾客，C15后 | `await checkApi('/orders/<O1>/refund', 'POST')` | 200，返回原退款结果 |
| 顾客，C13后 | `await checkApi('/usage')` | 200，核对对应调用的account_id和上游消耗字段 |
| 店员 | `await checkApi('/products', 'POST', {})` | 403，无商品维护权限 |
| 店员 | `await checkApi('/accounts/<A>', 'PUT', {})` | 403，无账号维护权限 |
| 店员 | `await checkApi('/accounts/<A>', 'DELETE')` | 403，无账号删除权限 |
| 店员，O4删除前 | `await checkApi('/orders/<O4>', 'DELETE')` | 403，无订单物理删除权限 |
| 店员 | `await checkApi('/orders/<O1>/settle', 'POST')` | 403，无结算权限 |
| 店员，T1已完成 | `await checkApi('/restocks/<T1>/complete', 'POST', {actual_amount:'8000'})` | 409，不能重复增加库存 |
| 管理员，A14 | `await checkApi('/orders/<O1>/settle', 'POST')` | 200，结算幂等 |
| 管理员 | `await checkApi('/orders/<O1>', 'DELETE')` | 409，不能删除已完成订单 |
| 管理员 | `await checkApi('/orders', 'POST', {items:[{product_id:<P>,quantity:1}]})` | 403，员工不能冒充顾客下单 |
| 管理员 | `await checkApi('/usage', 'POST', {product_id:<P>,tokens_used:'1'})` | 403，员工不能冒充顾客消费 |

补验CSRF时，在当前登录页面单独执行 `fetch('/api/v1/orders', {method:'POST',headers:{'Content-Type':'application/json'},body:'{}'}).then(async r => ({status:r.status,body:await r.json()}))`，预期403，不创建订单。非法输入、业务失败和越权响应都应保持统一JSON结构，包含请求编号；不得出现SQL语句、堆栈或连接路径。

可再在商品搜索输入 `'; DROP TABLE Users;--`，应作为普通搜索文本处理，页面仍能清空搜索后正常查询；不要在数据库客户端执行此文本。关闭弹窗、刷新页面以及退出后重新登录，都不应让已保存的交易消失。

### 8. 全职责覆盖与结束核对

| 已实现操作 | 人工步骤 |
|---|---|
| 登录、登录失败、退出与身份切换 | G3/G4、各阶段换身份 |
| products.list / save / delete | G1/G2、A1～A4、S1、A11/A15 |
| orders.list / get / create | C1～C10、C19/C20、S2、A8 |
| orders.item_add / item_set / item_delete | C2～C7、C8 |
| orders.pay / cancel / delete | C9/C11/C12、S3、A9/A12 |
| usage.list / create 与 balances.list | C13/C14/C18/C19、S2、A8 |
| inventory.list 与 accounts.save / delete | A5～A7、S4、A8/A11 |
| restocks.list / create / complete | S4～S6、A10 |
| refunds.list / request / settle | C15～C20、S2、A13/A14 |

- [ ] 四种角色入口、正确/错误登录、退出、搜索、空状态已核对；有足够数据时再核对翻页。
- [ ] 顾客的草稿明细增改删、同商品合并、价格快照、取消、支付和消费已核对。
- [ ] 未消费退款、部分消费退款、全部消费拒退、重复支付拒绝和退款幂等已核对。
- [ ] 第二顾客的数据隔离，以及店员/管理员的跨顾客只读查询已核对。
- [ ] 店员创建/完成补货、管理员继承这些职责，以及必要删除的成功/拒绝路径已核对。
- [ ] 页面隐藏按钮与直接API权限一致；CSRF、非法输入和失败反馈均已核对。
- [ ] 截图、对象编号、操作前后值及失败请求编号已记录；普通Windows账户的部署验收按应用手册另外记录，不能由本流程代替。

### 9. 验收后关闭服务器

先保存验收记录、截图、对象编号和失败请求编号，并点“退出登录”。**退出账号或关闭浏览器标签页不会停止服务器**，还需要按本次采用的启动方式执行下面步骤。

#### 9.1 关闭前台预览服务器

回到第0.2节启动服务的终端A，按一次 `Ctrl+C`，等待 Python/Waitress 退出并返回 PowerShell 命令提示符，再执行第9.3节。不要在终端B按 `Ctrl+C` 后就认为终端A的服务器已关闭。结束后可在终端A清除本轮运行环境变量：

```powershell
Remove-Item Env:DB_LAB_PREVIEW -ErrorAction SilentlyContinue
Remove-Item Env:DB_LAB_SECRET -ErrorAction SilentlyContinue
Remove-Item Env:DB_LAB_APP_DATABASE -ErrorAction SilentlyContinue
Remove-Item Env:DB_LAB_SERVER -ErrorAction SilentlyContinue
Remove-Item Env:DB_LAB_PORT -ErrorAction SilentlyContinue
```

#### 9.2 关闭普通账户计划任务服务器

仅用于第0.3节的启动方式。在有权限管理该任务的 PowerShell 中执行：

```powershell
$taskName = 'TokenHub-TokenHubWeb'
# 禁用以防验收后重启电脑又自动启动；下次按0.3节启用并启动即可。
Disable-ScheduledTask -TaskName $taskName | Out-Null
Stop-ScheduledTask -TaskName $taskName
Get-ScheduledTask -TaskName $taskName | Select-Object TaskName, State
```

任务预期为 `Disabled`。停止任务后仍需确认端口已释放，不能只根据任务状态断言子进程已经退出。这里不删除任务、账户或数据库，保留下次验收所需配置。

#### 9.3 确认端口释放并保留记录

停止后稍等片刻，在终端B执行：

```powershell
$listeners = Get-NetTCPConnection -LocalPort 5050 -State Listen -ErrorAction SilentlyContinue
if ($listeners) {
    $listeners | Select-Object LocalAddress, LocalPort, OwningProcess
    throw '5050仍有监听，请核对本轮服务器进程，尚不能登记为已关闭'
}
'5050端口已释放，Web服务器已关闭'
```

正常结果是没有监听记录，并输出关闭提示；重新访问页面或商品接口应无法连接，不能仅根据浏览器保留的旧画面判断服务器仍在运行。如果仍有监听，核对 `OwningProcess` 及对应的启动终端/计划任务，只处理本轮服务器，不批量终止Python或其它服务。关闭Web应用**不需要停止SQL Server服务**，不删除或回滚本轮已保存的订单、调用、退款和补货数据。

- [ ] 已记录启动方式、实际数据库、端口和验收时的Git提交。
- [ ] 已退出登录，保存人工检查结果及必要证据。
- [ ] 已停止本轮前台进程或计划任务，并确认5050无监听。
- [ ] 验收记录注明“服务已关闭”；数据库、日志和样例账户继续保留。
