# 第二阶段项目展示流程（按12页PPT顺序）

对应文件为《第10周_组长阮依成_第2阶段展示.pptx》，共12页。本文按当前`demonstration`分支的页面、按钮和SQL入口编写。

主线是同一笔订单从下单、支付、调用走到部分退款，再补充未消费退款、补货和异常验证。界面中的“店长”对应“管理员”。本文列出操作预期，执行时按现场结果核对。

## 页码与功能对应

| PPT页 | 核心内容 | 现场展示入口 |
|---|---|---|
| 1 | 项目与第二阶段成果 | PPT封面，浏览器保持游客商品目录 |
| 2 | 选购、订单明细、支付、调用、库存联动与价格快照 | 商品目录 → 订单管理 → Token余额 → 调用记录 |
| 3 | 18表、22外键、四类角色、75项测试与迁移结果 | SSMS结构查询、历史验收文件 |
| 4 | 完整ER模型 | PPT中的ER图；需要放大时打开项目ER图片 |
| 5 | 顾客/订单/商品、账号/库存/流水、角色/员工/补货联系 | 订单详情、库存页、ER图、受引用删除拒绝 |
| 6 | UsageSummary拆分与BCNF、无损迁移 | 规范化文档、迁移日志与v1.0查询 |
| 7 | 顾客注册、管理员新增/停用员工 | 注册弹窗、员工管理、第二浏览器窗口 |
| 8 | 四类角色权限 | 切换游客、顾客、店员、管理员，核对导航与按钮 |
| 9 | 旧样例时间顺序异常与改进 | 历史异常日志、当前库只读时间检查 |
| 10 | 部分消费退款、未消费退款、重复退款保护 | 订单管理 → 退款账本 → Token余额 |
| 11 | 大屏、14天趋势、库存预警与补货 | 运营概览 → 上游库存 → 补货任务 → 运营概览 |
| 12 | 401/403/409/400与数据库对账 | 浏览器开发者工具、注册/商品表单、SSMS及历史证据 |

## 展示前准备

### 0.1 环境与窗口

1. 在PowerShell进入`D:\Desktop\DB\DB_lab`，按[README复现与启动流程](../README.md)选择新建库或已有库补装路径，记录本轮RunId及v1.1库名。
2. 执行README中的`seed_dashboard_recent.py`步骤，确认输出覆盖14天，再完成下方0.2节的准备命令，然后按README启动Web。保留启动服务的PowerShell窗口，结束时回到该窗口停止服务。
3. 打开浏览器，地址栏输入`http://127.0.0.1:5050/`，按Enter。后续步骤按5050端口编写，自定义端口时替换。
4. 打开PPT，按F5进入放映。放映时用方向键翻页，用Alt+Tab在PPT与浏览器之间切换。
5. 打开SQL Server Management Studio（SSMS）。在“连接到服务器”中，服务器名称填`localhost\SQLEXPRESS`，身份验证选“Windows身份验证”，点击“连接”。自定义SQL实例按实际配置填写。
6. SSMS工具栏点击“新建查询”，在数据库下拉框选择本轮`TokenHubDB_v11_<RunId>`。本文SQL均为只读查询。
7. 在Windows资源管理器地址栏输入`D:\Desktop\DB\DB_lab`并按Enter，便于打开后面引用的日志。PPT截图与历史证据的编号不作为本轮新建记录的编号。

### 0.2 用命令准备商品、库存和陈同学的账户

完成README的建库和近14天样例步骤后，在启动服务器之前，用同一个PowerShell窗口执行下面命令。保留README中实际设置的`$ServerInstance`和`$DatabaseName`。

```powershell
.\.venv\Scripts\python.exe tools/prepare_ppt_demo.py --server $ServerInstance --database $DatabaseName
if ($LASTEXITCODE -ne 0) { throw 'PPT数据准备失败，请按输出检查，暂不开始展示' }
```

本流程账户统一使用密码`cshztmdscshztmds`。脚本直接为`chen_demo`和`web_admin`设置该密码，并撤销这两个账户的旧会话。第7页注册顾客和新增店员时也填写这个密码。

成功时输出`PASS`和大屏基准JSON的完整路径，该文件保存在本批次的`result/webapp`目录内。自动完成以下准备。

- 创建顾客`chen_demo`，邮箱`chen_demo@example.invalid`，保持没有订单、调用和Token余额。
- 创建或设置商品`入门体验套餐`，Other、单价6.90、100000 Token、每套餐上游消耗100000、在售。已有Other＋100000档位时，将该档位名称及当前价格设为这些值。
- 创建`展示库存账号`，Other、初始额度10000、安全阈值20000、有效、一年后到期，并检查配对库存为10000。
- 检查另有有效的Other账号能承接20000 Token调用。
- 保存总订单、模拟已付金额、模拟退款金额及低库存账号数，供第11页核对。

准备成功后，继续README启动命令，打开`http://127.0.0.1:5050/`并保持游客身份，即可从第1页开始。第2页直接用`chen_demo`和密码`cshztmdscshztmds`登录。

脚本使用Windows集成认证，由README建库所用的数据库准备身份执行。所有数据准备在同一事务中完成，失败会回滚。准备后尚未开始展示时，可以直接重跑。`chen_demo`已有交易、库存已补货，或者第7页的`li_demo`、`zhang_staff`已存在时，脚本提示按README新建批次。

第7页仍现场注册`li_demo`和创建`zhang_staff`。`展示库存账号`的10000额度低于本次调用需要的20000，调用由另一个充足的Other账号承接，它保留给第11页的预警和补货。

## PPT第1页：项目封面

**核心功能**　说明展示对象是API Token中转站第二阶段，建立游客起点。

1. 停在PPT封面，说明项目包含套餐交易、Token调用与库存补货。
2. Alt+Tab切到浏览器，显示游客“商品目录”，指出右上角“登录账户”和商品行“登录购买”。
3. 此时保持游客身份，翻到PPT第2页。

## PPT第2页：从选套餐到调用，保留一笔订单走到退款

**核心功能**　订单和明细、成交快照、支付发放Token、调用扣余额与库存。6.90元订单留到第10页再退款。

| 步骤 | 点击和输入 | 现场核对 |
|---|---|---|
| 2-1 | 右上角“登录账户” → 登录入口选“顾客登录” → 账号填`chen_demo`，密码填`cshztmdscshztmds` → 点“登录”。 | 顾客只能看到本人的交易导航。 |
| 2-2 | 左侧“商品目录” → 表格上方搜索框输入`入门体验套餐` → 点“搜索” → 入门体验套餐行点“选购”。 | 创建订单弹窗选中了入门体验套餐，数量1。 |
| 2-3 | 核对入门体验套餐单价6.90、数量1 → 点“提交订单”。 | 自动转到“订单管理”，找到最新一行金额为6.90的订单，状态“待处理”。这里表示待支付。 |
| 2-4 | 6.90元订单行点“详情”。 | 显示单价6.90、数量1、总金额6.90、Token100000。点弹窗右上角“×”关闭。 |
| 2-5 | 右上角“退出登录” → “登录账户” → 员工登录`web_admin`，密码填`cshztmdscshztmds` → 左侧“商品目录” → 搜索`入门体验套餐` → 入门体验套餐行“编辑” → “单价”改8.90 → “确认提交”。 | 商品当前价格变为8.90。 |
| 2-6 | 管理员保持登录 → 左侧点“上游库存” → 查看“模型供应商”为Other的账号；有多页时点表格底部“下一页”。截下状态有效、尚未到期且可用额度至少20000的Other账号，保留“账号编号”“账号名称”和“可用额度”三列。 | 保存调用前库存。`展示库存账号`只有10000额度，这次调用会使用另一个额度充足的Other账号。 |
| 2-7 | 右上角“退出登录” → 点“登录账户” → 选“顾客登录” → 账号填`chen_demo`，密码填`cshztmdscshztmds` → 点“登录” → 左侧“订单管理” → 6.90元订单行点“详情”。 | 订单金额仍为6.90，商品现价已为8.90。关闭弹窗。 |
| 2-8 | 6.90元订单行点“模拟支付” → 在“确认操作”弹窗点“确认提交”。 | 6.90元订单为“已支付”。 |
| 2-9 | 左侧点“Token 余额”。 | Other余额100000，展示支付后到账。 |
| 2-10 | 左侧“调用记录” → 右上角“模拟调用” → 商品下拉选择`入门体验套餐` → “消费 Token”填20000 → 点“确认提交”。 | 产生一条20000 Token调用记录。 |
| 2-11 | 左侧点“Token 余额”，再返回“调用记录”。 | 余额80000，并保留调用流水。6.90元订单暂不退款。 |
| 2-12 | 右上角“退出登录” → 点“登录账户” → 登录入口选“员工登录” → 账号填`web_admin`，密码填`cshztmdscshztmds` → 点“登录” → 左侧点“上游库存”。按调用前截图中的账号编号找到相同账号，有多页时点“下一页”，对比“可用额度”。 | 本次使用的Other账号可用额度减少20000。例如调用前为100000000，调用后应为99980000。`展示库存账号`仍为10000，留到第11页补货。 |
| 2-13 | 右上角“退出登录” → 点“登录账户” → 选“顾客登录” → 账号填`chen_demo`，密码填`cshztmdscshztmds` → 点“登录” → 左侧点“订单管理”。 | 恢复陈同学登录，便于第5页继续查看6.90元订单。 |

本套餐按1:1换算，顾客消费20000 Token，对应上游可用库存减少20000。对比调用前后同一账号编号的截图，核对“调用前可用额度－调用后可用额度＝20000”。有多个符合条件的Other账号时，服务端按账号编号从小到大选择，调用前保留这些账号的截图即可定位变化。展示期间只进行这一次调用，待库存对比完成后再继续其它操作。第11页继续展示补货。

## PPT第3页：第二阶段成果与证据

**核心功能**　结构规模、可信外键、角色和既有测试成果。

1. 保持PPT第3页，切到SSMS，在数据库下拉框选择本轮v1.1库。
2. 点“新建查询”，粘贴下面SQL，按F5。结果应为18张表、22条启用可信外键。

```sql
SELECT COUNT(*) AS table_count FROM sys.tables WHERE is_ms_shipped=0;
SELECT COUNT(*) AS trusted_foreign_key_count
FROM sys.foreign_keys WHERE is_disabled=0 AND is_not_trusted=0;
```

## PPT第4页：完整ER模型

**核心功能**　18张表按身份、交易、余额、库存和账务划分职责。

1. 停留第4页完整ER图，按“身份 → 订单/明细 → 余额/调用 → 账号/库存 → 退款”顺序指出实体。
2. 图过小时，Alt+Tab切资源管理器，在地址栏输入`D:\Desktop\DB\DB_lab\report\er_diagram_app.png`并按Enter，打开18表模型查看。
3. 指出`Orders—OrderDetails—Products`、`UpstreamAccount—Inventory—InventoryLog`、`OrderDetails—OrderTokenLots`、`Orders—RefundLedger`四组联系，再回PPT第5页。

## PPT第5页：设计关系落到页面和数据

**核心功能**　多对多联系由明细承接；库存快照与流水分离；员工角色和任务职责分开。

| 步骤 | 点击和输入 | 核心展示 |
|---|---|---|
| 5-1 | 保持`chen_demo`登录 → 左侧“订单管理” → 6.90元订单行“详情”。 | 同一订单通过明细引用商品，明细保留数量及6.90快照；商品现价已为8.90。关闭弹窗。 |
| 5-2 | 退出陈同学 → 员工入口登录`web_admin`，密码填`cshztmdscshztmds` → “商品目录” → 搜索`入门体验套餐` → 入门体验套餐行“删除” → 弹窗点“确认提交”。 | 受订单引用的商品删除被拒绝，入门体验套餐和6.90元订单仍保留，记录错误请求编号。点“取消”关闭弹窗。 |
| 5-3 | 左侧“上游库存”，用表格底部“下一页”找到展示库存账号，核对账号编号与10000可用量。 | 账号与库存快照配对。此处先不补货。 |
| 5-4 | 回PPT第5页，指出Roles、Employees、RestockTask的两个员工外键。 | 第11页人工补货将记录创建人和处理人。 |

本项目通过约束和新增账号时的受控写入保证账号有配对库存。PPT中“每个补货任务必须有创建人”在本次人工任务成立；系统自动任务允许created_by为空，展示时加上“人工”限定。

## PPT第6页：规范化迁移与数据保留

**核心功能**　将周期定义从使用汇总中拆出，验证记录保留与无损重构。

1. 切到资源管理器 → 打开`archive\coursework\week6\dependency_normalization.md`，查找`UsagePeriod`，对照PPT说明周期类型＋开始日期决定结束日期。
2. 打开`result\week6\v11\WebFinal1106A\regression_v11.sql.log`，Ctrl+F查找`R02`和`EXCEPT`，展示历史双向比较通过记录。也可打开本轮RunId对应的同名日志。
3. SSMS点击数据库下拉框，选择本轮`TokenHubDB_v10_<RunId>` → 点“新建查询” → 粘贴以下SQL → F5。

```sql
SELECT COUNT_BIG(*) AS summaries FROM dbo.UsageSummaryCore;
SELECT COUNT_BIG(*) AS reconstructed_summaries FROM dbo.UsageSummary;
SELECT COUNT_BIG(*) AS period_definitions FROM dbo.UsagePeriod;
SELECT TOP (5) period_type,period_start,period_end
FROM dbo.UsagePeriod ORDER BY period_type,period_start;
```

4. 核对3394、3394、99，指出周期终点集中在UsagePeriod保存。若本轮做过其它汇总写入，以构建时的迁移日志说明3394这一历史数值。
5. 回PPT第6页，说明两张拆分表基于已确认函数依赖达到BCNF。订单金额等业务快照仍由现有约束和交易过程维护。

## PPT第7页：注册、创建员工、停用和会话失效

**核心功能**　顾客自行注册；管理员管理普通店员；停用保留记录并撤销会话。

### 7.1 注册李同学的顾客账户

1. 浏览器右上角“退出登录” → “登录账户” → 点“还没有账号？注册顾客账户”。
2. 账号输入`li_demo`，邮箱输入`li_demo@example.invalid`，密码及确认密码输入`cshztmdscshztmds`。
3. 点“创建顾客账号”，核对自动以顾客登录。
4. 左侧点“订单管理”，李同学应看不到陈同学的6.90元订单。李同学保持无订单，留给第8、12页隔离验证。

### 7.2 新增和停用张店员

| 步骤 | 点击和输入 | 核对结果 |
|---|---|---|
| 7-1 | 退出李同学 → 员工入口登录`web_admin`，密码填`cshztmdscshztmds` → 左侧“员工管理” → 右上角“新增店员”。 | 表单只能创建普通店员。 |
| 7-2 | “姓名”填“张店员”，“登录账号”填`zhang_staff`，“初始密码”“确认密码”填`cshztmdscshztmds` → 点“创建店员”。 | 列表出现张店员，状态在职。 |
| 7-3 | 张店员行点“修改姓名” → “姓名”改为“张店员（客服）” → “确认提交”。 | 姓名更新，编号保留。 |
| 7-4 | 从浏览器右上角菜单“…”打开新的InPrivate/无痕窗口，在地址栏输入网站地址 → 登录账户 → 登录入口选“员工登录” → 账号输入`zhang_staff` → 填`cshztmdscshztmds` → 点“登录”。 | 第二窗口以店员登录；普通窗口仍为管理员。 |
| 7-5 | 回普通窗口 → 张店员行点“停用” → 在停用弹窗点“确认提交”。 | 张店员行保留，显示已停用，并出现“重新启用”。 |
| 7-6 | 切到张店员的无痕窗口 → 点击左侧“订单管理”。 | 原会话请求被拒绝，出现需重新登录的错误及请求编号。不能继续操作业务。 |
| 7-7 | 回普通窗口 → 张店员行“重新启用” → “确认提交”。 | 状态恢复。张店员旧会话已撤销，重新登录后才可使用。 |
| 7-8 | 张店员无痕窗口右上角“退出登录” → “登录账户” → 登录入口选“员工登录” → 账号输入`zhang_staff` → 填`cshztmdscshztmds` → 点“登录”。 | 新会话登录成功，保留该窗口用于第11页补货。 |

PPT截图还显示“重置密码”按钮。需要展示时，在普通窗口点击张店员行“重置密码” → 新密码与确认新密码均填`cshztmdscshztmds` → “确认提交”，然后在张店员窗口退出并用`cshztmdscshztmds`登录。

## PPT第8页：四类角色的实际操作边界

**核心功能**　同一系统按身份提供不同入口，顾客只读本人订单。

| 身份 | 具体点击路径 | 预期与对应权限 |
|---|---|---|
| 游客 | 普通窗口退出管理员 → “商品目录” → 入门体验套餐行“登录购买”。 | 可以看在售商品，购买触发登录；注册入口只提供顾客注册。点“取消”关闭。 |
| 顾客李同学 | “登录账户” → 登录入口选“顾客登录” → 账号输入`li_demo` → 填`cshztmdscshztmds` → 点“登录” → “订单管理” → “Token 余额”。 | 只能看到李同学自己的数据，看不到陈同学的6.90元订单；没有库存、员工管理导航。 |
| 张店员 | 切张店员的无痕窗口 → “商品目录” → “订单管理” → “上游库存” → “补货任务” → “退款账本”。 | 能查看跨顾客运营数据，可看到6.90元订单；没有新增商品、员工管理、替顾客支付或申请退款的按钮。 |
| 管理员 | 普通窗口退出李同学 → 员工入口登录`web_admin`，密码填`cshztmdscshztmds` → “商品目录” → “员工管理”。 | 可维护商品及店员，原有员工和历史交易保留。 |

管理员、店员都不以员工身份替顾客支付。第12页会直接调用隐藏入口后的API，证明后端也检查权限。

## PPT第9页：旧数据时间异常与当前检查

**核心功能**　展示已发现的历史问题、保留证据，以及当前的跨表时间校验。

1. 停留PPT第9页，指出旧库案例中的订单日期和注册日期。
2. 资源管理器打开`result\week6\regression\legacy_anomalies_source.log`，核对`orders_before_registration 20`及`usage_before_registration 402`。
3. 说明该日志来自历史`TokenHubDB_v01_A`，旧库已清理时直接使用留存证据。
4. SSMS把数据库下拉框切回本轮v1.1库 → “新建查询” → 粘贴以下SQL → F5。

```sql
SELECT COUNT(*) AS orders_before_registration
FROM dbo.Orders o JOIN dbo.Users u ON u.user_id=o.user_id
WHERE o.created_at<u.created_at;
SELECT COUNT(*) AS usage_before_registration
FROM dbo.TokenUsageLogs l JOIN dbo.Users u ON u.user_id=l.user_id
WHERE l.used_at<u.created_at;
```

5. 新建干净库预期为0和0。时间保护来自注册、订单、调用的跨表规则与受控入口；第6页的周期拆分解决的是函数依赖，两者分别说明。

## PPT第10页：退款闭环与重复请求

**核心功能**　已用Token保留消费事实，未用部分回收并登记应退款项；重复退款不重复记账。

### 10.1 对6.90元订单申请部分退款

| 步骤 | 点击和输入 | 预期 |
|---|---|---|
| 10-1 | 普通窗口退出管理员 → 点“登录账户” → 登录入口选“顾客登录” → 账号输入`chen_demo` → 填`cshztmdscshztmds` → 点“登录” → 左侧“Token 余额”。 | Other余额80000。 |
| 10-2 | 左侧“订单管理” → 6.90元订单行“申请退款” → 确认弹窗点“确认提交”。 | 6.90元订单变为“部分退款”。 |
| 10-3 | 左侧“退款账本”，按订单编号找到6.90元订单。 | 应退5.52、回收80000、已消费20000，状态待模拟结算。 |
| 10-4 | 左侧“Token 余额”。 | Other余额0，未消费Token已回收。 |

### 10.2 再买一笔8.90元订单，展示未消费退款

1. 左侧“商品目录” → 搜索`入门体验套餐` → 入门体验套餐行“选购” → 数量1 → “提交订单”，找到新产生的8.90元订单。
2. 8.90元订单行“详情”，核对采用商品当前价8.90，Token100000；关闭弹窗。
3. 8.90元订单行“模拟支付” → “确认提交”，再点“Token 余额”，核对到账100000。
4. 保持未调用，返回“订单管理” → 8.90元订单行“申请退款” → “确认提交”。
5. 点“退款账本”，核对8.90元订单应退8.90、回收100000、已消费0。再点“Token 余额”，回到0。

### 10.3 重复提交同一笔退款

6.90元订单已退款后按钮会隐藏，用开发者工具重复同一个请求。

1. 陈同学保持登录，按F12打开开发者工具 → 点击“控制台/Console”。浏览器首次限制粘贴时，按其提示在本机允许本次粘贴。
2. 粘贴下面函数并按Enter。函数只输出HTTP状态、业务码和请求编号。

```javascript
async function pptApi(path, method = 'GET', payload = {}) {
  const identity = await (await fetch('/api/v1/auth/session')).json();
  const options = {method, headers: {
    'Content-Type': 'application/json', 'X-CSRF-Token': identity.data.csrf
  }};
  if (method !== 'GET') options.body = JSON.stringify(payload);
  const response = await fetch('/api/v1' + path, options);
  const body = await response.json();
  console.table([{http: response.status, code: body.code, request_id: body.request_id}]);
}
```

3. 继续复制下面这段代码并按Enter。它会从当前顾客的订单中自动找到6.90元那笔，再提交同一退款请求。

```javascript
{
  const orderList = await (await fetch('/api/v1/orders')).json();
  const partialRefundOrder = orderList.data.items.find(order => Number(order.total_amount) === 6.90);
  if (!partialRefundOrder) throw new Error('请先用chen_demo登录，并完成6.90元订单');
  await pptApi('/orders/' + partialRefundOrder.order_id + '/refund', 'POST');
}
```

4. 预期200。按F12关闭工具，点击“订单管理”，再点“退款账本”重新加载。6.90元订单仍只有一笔退款，余额仍0。
5. 需要展示RF01—RF06证据时，打开`result\week6\v11\WebFinal1106A\validation_10_refund_regression.sql.log`，Ctrl+End查看PASS结果。

## PPT第11页：大屏变化、预警与补货

**核心功能**　业务操作进入SQL统计，预警来自库存与阈值比较，补货按实际量入库。

| 步骤 | 点击和输入 | 预期 |
|---|---|---|
| 11-1 | 普通窗口退出陈同学 → 员工入口登录`web_admin`，密码填`cshztmdscshztmds` → 左侧“运营概览” → “立即刷新”。 | 对比准备命令输出的基准JSON（total_orders、gross_paid_amount、refund_amount），总订单增加2笔、模拟已付金额增加15.80元、模拟退款金额增加14.42元。截图旧值102/4298.50不作为本轮目标。 |
| 11-2 | 观察“近14天订单趋势”，等待刷新时间更新，或点“立即刷新”。 | 14天样例形成趋势，今天额外包含本轮两笔订单。 |
| 11-3 | 向下滚动到“上游库存预警”。 | 展示库存账号满足10000＜20000，存在对应预警条件。列表最多5条，未显示展示库存账号时用预警总数及库存页核对。 |
| 11-4 | 切张店员的无痕窗口 → 左侧“上游库存” → 用“下一页”找到展示库存账号 → 展示库存账号行点“补货”。 | 打开“创建补货任务”，账号编号已自动填好，保持原值。 |
| 11-5 | 保留自动填入的账号编号，“计划补货数量”填25000 → “确认提交”。 | 创建任务，`展示库存账号`的可用库存仍为10000。 |
| 11-6 | 左侧“补货任务”，在最新任务中找到账号名称为`展示库存账号`、计划25000的那条最新任务。 | 计划25000，状态待处理；创建任务本身不入库。 |
| 11-7 | 补货任务行“完成补货” → “实际补货”填20000 → “确认提交”。 | 补货任务已完成，实际20000；不会按计划25000增加。 |
| 11-8 | 左侧“上游库存” → 翻页到展示库存账号。 | `展示库存账号`的可用库存为30000。 |
| 11-9 | 回普通窗口管理员“运营概览” → “立即刷新” → 滚动到预警区域。 | 展示库存账号不再满足低库存条件，预警账号数较补货前减少1。 |

若要展示创建人和处理人，SSMS选本轮v1.1库，直接执行下面SQL。查询按账号名称自动找到刚才那笔任务。

```sql
SELECT TOP (1) t.task_id,t.created_by,t.assigned_to,t.target_amount,t.actual_amount,t.status
FROM dbo.RestockTask t
JOIN dbo.UpstreamAccount a ON a.account_id=t.account_id
WHERE a.account_name=N'展示库存账号'
ORDER BY t.task_id DESC;
```

本次创建和处理均由张店员完成，对应同一员工编号。回到PPT时指出库存变化与SQL记录一致。

## PPT第12页：四种失败反馈与SQL对账

**核心功能**　显示明确HTTP状态与请求编号，验证失败没有产生业务写入。

以下控制台命令使用第10页的`pptApi`函数。若刷新过页面，在当前页面Console重新粘贴该函数。下面的权限检查使用新库自带的第1号订单和第1号商品，可以直接复制命令。

| 场景 | 具体点击/输入 | 核对结果 |
|---|---|---|
| 401游客请求订单 | 普通窗口退出管理员 → F12 → Console → 输入`await pptApi('/orders')` → Enter。 | HTTP401，未登录，记录请求编号。 |
| 403顾客查看别人订单 | F12收起 → “登录账户” → 登录入口选“顾客登录” → 账号输入`li_demo` → 填`cshztmdscshztmds` → 点“登录” → F12/Console → `await pptApi('/orders/1')`。 | HTTP403。第1号订单属于初始样例顾客，李同学无权查看。 |
| 403顾客访问库存 | 李同学保持登录 → Console输入`await pptApi('/inventory')`。 | HTTP403，证明绕过隐藏导航也被拒绝。 |
| 400非法Token数量 | 李同学保持登录 → Console输入`await pptApi('/usage', 'POST', {product_id: 1, tokens_used: '-1'})`。 | HTTP400，不新增调用。数字输入框本身可能先拦截负数，所以此处直接验证API。 |
| 409重复注册 | 收起F12 → 退出李同学 → 登录账户 → 注册顾客入口 → 账号填`li_demo`、邮箱填`li_demo@example.invalid`，密码及确认密码均填`cshztmdscshztmds` → F12打开“网络/Network” → 再点击“创建顾客账号”。 | 页面提示重复并显示请求编号。Network中选POST auth/register → “标头/Headers”看409。收起工具，点“取消”关闭表单。 |
| 409商品唯一约束 | 员工入口登录`web_admin`，密码填`cshztmdscshztmds` → 商品目录 → 新增商品 → 新名称`重复档位套餐`、Other、100000 Token、单价6.90、上游消耗100000、在售 → F12打开Network → 再点击“确认提交”。 | 因入门体验套餐已占用Other＋100000档位而409；选POST products看状态。取消弹窗后新商品未出现。 |

### 最后对账

1. SSMS选本轮v1.1库 → 新建查询。
2. 粘贴以下查询，账号已写成`chen_demo`，按F5。

```sql
SELECT o.order_id,o.status,o.total_amount,o.total_tokens,
       l.issued_tokens,l.consumed_tokens,l.refunded_tokens,
       r.refund_amount,r.refundable_tokens,r.consumed_tokens AS refund_consumed
FROM dbo.Orders o
JOIN dbo.Users u ON u.user_id=o.user_id
JOIN dbo.OrderDetails d ON d.order_id=o.order_id
LEFT JOIN dbo.OrderTokenLots l ON l.detail_id=d.detail_id
LEFT JOIN dbo.RefundLedger r ON r.order_id=o.order_id
WHERE u.username='chen_demo' ORDER BY o.order_id;
SELECT b.model_provider,b.remaining_tokens
FROM dbo.TokenBalances b JOIN dbo.Users u ON u.user_id=b.user_id
WHERE u.username='chen_demo';
```

3. 核对6.90元那笔订单购买100000 Token、消费20000、回收80000、退款5.52元；8.90元那笔订单购买100000 Token、消费0、回收100000、退款8.90元。陈同学的Other余额应为0。
4. 打开`result\stage2\WebEmp26A01\README.md`，查看22张业务截图与25项SQL对账的证据入口。75项日志仍使用第3页的WebFinal1106A路径，分别说明批次。
5. 回PPT第12页完成展示。保存交易结果截图、失败请求编号及必要的对账结果。

## 结束与口径核对

- 在普通窗口与张店员的无痕窗口分别点“退出登录”。回到启动服务器的PowerShell窗口，按Ctrl+C，等待命令提示符返回，再按README检查5050端口释放。
- 需要清理本轮数据时，按[README完整批次清理](../README.md)输入本轮RunId，先预览再执行；清理后按文档核对三个数据库及四个批次目录。
- 3394为迁移汇总行数，75/22/25是对应历史批次结果。大屏金额和订单数以本轮基准变化核对。
- 时间线合法性由跨表时间约束与受控交易过程保证，周期表拆分处理函数依赖。人工补货有创建人，系统自动任务允许为空。
- 本流程按12页PPT及当前源码静态核对，尚未登记为本轮逐项人工执行通过。PPT源文件保持原样。
