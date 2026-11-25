# 第三阶段（第10—13周）AI 使用详细日志

仅记录第10周及之后的数据库程序对象、事务、测试与交付整理；更早的历史记录已归档。

## 2026-11-11 第10周计划与上下文复核

- 用户要求重新读取已变更项目与D:/Desktop/第10周任务讲解.docx，生成执行计划。
- 读取前git status --short为空，HEAD为afbcf54d3403d2492a031cd977cbf9c0a7c2826a。审查AGENT、README、ROADMAP、运行手册、SQL布局、表结构、应用过程、DAO/路由/服务、准备工具及WebFinal1106A和WebXY1105F记录。
- DOCX以zipfile和ElementTree提取段落及表格。首次输出编码不匹配，设置PYTHONIOENCODING=utf-8后完整重读。一次rg查询把Windows通配路径作为文件参数而失败，随后改用目录参数及精确路径重读。
- 发现manual流水禁止非空reference_id，计划改为调整记录以外键关联InventoryLog；历史已成交明细不可变触发器会影响快照回填，计划加入部署事务与保护恢复验证；现有total_quota>0约束限制清零校正，计划明确拒绝条件。
- 新增plan/week10-procedures-functions-plan.md。首次组合补丁因空更新hunk被拒绝，确认计划文件不存在且工作区无部分写入，再重新应用成功。
- 计划范围为第10周，记录第11—13周衔接。建议按金额阶梯折扣、账号维度库存校正、SQL计算与受控页面调用实施，建议规则待审核。
- 同步README、ROADMAP与两份AI记录。静态验证结果在本条之后补记。数据库测试、服务启动、浏览器检查及第10周实施待执行。

- 静态验证结果为PASS。3段PowerShell命令经Parser.ParseInput解析无错误，计划3个相对链接存在，必需对象/测试预期/未勾选实施步骤及AI记录检查通过，git diff --check退出码0。命令仅作语法解析。


## 2026-11-11 第10周实施启动

用户授权按计划执行，采用计划中的折扣、管理员校正及补货口径。工作直接在原目录的week10-procedures-functions分支进行。SQL和Web由子任务按文件归属实施，提交和文档集中核对。

Web反例先运行5项，出现4个缺少dao.week10错误和1个数值精度断言失败，随后进入实现。新后缀WebW10Base01已从v0.1完整建立至Web，准备退出码0，记录在result/week10/WebW10Base01/prepare.log。当前运行旧业务完整回归，尚未登记结果。SQL审查发现现有订单包含partially_refunded状态，销售统计将同时计入以保留原成交额；空草稿需要Orders.pricing_rule_version保存版本，计划适配时补齐该字段。


### 第10周P0及SQL/Web实现进展

基线回归首次运行73项，1项模块导入错误，原因是归档后tests/test_backup_directory.py仍引用week6.v11。同步修正该测试和ER渲染入口为db_tools.v11，随后重跑。准备入口3项反例先运行为1失败2错误，新增--with-week10及受限目标安装函数后3项通过，Ruff通过。

SQL反例先在基线只读执行，因折扣函数缺失返回56999，退出1；随后新增schema、函数和过程。Web新增5项测试先红后绿，API角色/日期/有符号BIGINT/UUID与字段白名单、56xxx错误映射、数值字符串和页面已实现，node语法及Ruff通过，数据库联调待执行。开发库WebW10Dev01完整准备成功，原基线库保留。


### 2026-11-11 第10周进展

原业务基线重跑75项全部通过，0跳过，证据result/week10/WebW10Base01/unittest_attempt2.log。SQL开发库安装及初步回归均退出0，安装日志sql_install_attempt01.log和回归sql_regression_attempt01.log位于result/week10/WebW10Dev01。独立测试反例在基线只读确认折扣函数缺失208，随后实施集成测试。Web相关14项测试、Ruff及JS语法通过。


### 2026-11-11 第10周进展

SQL开发安装和回归通过后，审查补齐销售name字段契约、SQL入口允许字段/JSON类型及订单伪造字段拒绝。独立SQL测试初轮发现QUOTED_IDENTIFIER导致1934，SQL文件显式设置会话选项后重跑通过，失败日志保留。ER新增校正实体、4条外键和快照字段，首次渲染缺少新连接端口映射而报KeyError，补齐SIDES后重导。当前测试使用开发库独占运行。


### 2026-11-11 第10周进展

Web层17项相关测试通过，Ruff检查通过；格式检查发现ER脚本一行需折行，已格式化。SQL正例回归覆盖销售125元/2订单/4件、退款后保留成交额、校正+300/-400及重复键，开发库回归通过。SQL允许字段和JSON类型审查修正已完成。


### 2026-11-11 第10周进展

全新WebW10Final01通过--with-week10从空库安装，原v1.1回归先执行，周次安装后完成。SQL/API/页面模块已集成，静态SQL审查与参数边界修正完成。独立数据库测试仍在开发库运行，最终库暂不运行写测试。


### 2026-11-11 第10周进展

SQL/API和页面已分步本地提交。提交前diff检查曾提示sql/app/week10.sql末尾多空行，已去除；后续检查重新核验。第10周数据库集成初轮发现1934会话选项及夹具唯一键问题，已保留各尝试日志并修正，32项新增测试继续运行。ER目视核验19实体26关系后去掉长实体标题重复类型标签，修正标题重叠。


### 2026-11-11 第10周进展

新增39项测试在开发库全部通过，0失败0跳过，结果result/week10/SqlTestsAttempt07。覆盖26项SQL、准备入口和Web回归。验收工具拒绝基线库与重复证据目录，原结果哈希保持不变。浏览器第一次发现校正筛选参数400，已补反例并修复；原因改用UTF-16存储长度校验，SQL8115映射400。新增安装前后8表业务计数/校验和保存，正在WebW10Final02验证完整新库；另建专用回滚批次验证安装中断。


### 2026-11-11 第10周进展

安装强制失败实验已通过，sql/week10/test_install_rollback.sql触发56998后连接关闭回滚，校验新schema/字段不存在、保护触发器启用、8表计数/校验和与原值一致，证据WebW10Rollback1/rollback_result.json。全量114项首轮有1项错误码顺序回归，修复授权优先后原SQL13项和新SQL26项通过。浏览器第三次流程通过9张截图，第二次失败为脚本误用注册username字段，改为现有account字段后通过。为保持第二阶段报告图源与18表数据一致，第三阶段另存er_diagram_week10可编辑源/渲染脚本/SVG/PNG，原应用ER保留，更新增量数据字典。


### 2026-11-11 第10周进展

最终新库WebW10Final03从空链路安装成功，安装前后8表业务校验一致；完整115项unittest通过，0失败0跳过，full_unittest.log保留。最终审查发现校正响应丢失后可能换键，已保存待确认参数/操作键至sessionStorage，重开表单恢复原请求并锁定参数，新请求需显式新建；列表BIGINT total仅在Week10 DAO中转字符串，大数反例先红后绿。最终浏览器正在模拟服务端提交后响应丢失、关闭重开和原键重试。


### 2026-11-11 第10周进展

最终验证收尾：115项完整测试和40项周次逐例验收通过；新页面Edge10张截图通过，包括服务端已提交但响应丢失后的关窗恢复和原键重试，员工管理11张截图通过。旧业务追加脚本在补货/补货建议按钮重名处失败，保留18张过程/失败截图，定位改为exact=True，完整重跑待补做。Ruff、格式、JS语法和diff检查通过。已关闭本轮5052预览并核验无监听，shutdown.json保存结果。普通Windows身份仍待有效管理员权限，runtime_preflight.json记录false。


## 2026-11-11 补充提交现有复现结果

用户要求commit。检查工作区后，仅余WebNewRun01的源库、Web与v1.1复现输出未跟踪。本轮将这三个目录作为已有运行记录提交，未重新运行数据库或测试。提交前检查文件范围、凭据模式与git diff --check。


## 2026-11-11 直接在main提交

用户要求直接commit到main。已将week10-procedures-functions的全部提交快进合入main，工作区干净，并在AGENT.md记录后续直接在main本地逐步提交的约束。

## 2026-11-23 第12周复查与并发死锁修正

- 复查（另开AI会话，只读）：临时库WebXY1123V（391d95e，app_prepare第10—12周）。嵌套失败经app.[Execute]：54490/54491原样返回、数据回滚、无266；直接SQL外层事务中失败后@@TRANCOUNT 1→0；同一订单/补货单双连接并发10轮均一成一败（直接53131/53311，Web 55009）；6顾客×20单并发完成：直接死锁78/120、89/120，经Web 82/120，付款与调用混跑付款45/60失败，一致性0差异；临时副本过程对比：去掉预检查120/120、预检查前锁UpstreamAccount 120/120。新商品未挂分类、可挂根节点；depleted账号补货777000后可售余量不变；受限身份app_runtime_probe可自设w12.fail_point，仅本请求54490回滚。test_transactions.sql连跑两次12/12。清理脚本核验PASS。
- 肖懿决定“开始修吧”：只改问题1代码（order_transaction.sql加一条UPDLOCK,HOLDLOCK锁供应商账号行），其余写文档。
- 更正：前文“Web支付经w12.usp_CompleteOrder加锁后核对，不受影响”仅指无超卖，未考虑死锁；原句保留。
- 复测WebXY1124A：app_prepare退出0；test_transactions 12/12、TRANCOUNT=0；test_week11_12_sql 9 OK；全量124 OK；ruff check/format（webapp tests tools）通过，对全仓库运行时db_tools旧脚本20项原有问题，不在范围内未改。压测脚本stress.py、alter.py存入证据目录：修改后直接/Web均120/120；修改前（按文件去掉锁临时替换）直接死锁84/120、Web 83/120。首次压测修改前一轮因测试商品唯一键冲突未执行、恢复脚本有误，修正后整组重跑，日志为重跑结果。
- 文档：week12_report.md补嵌套事务说明、Web重复操作55009、分类维护限制、表关系表、不重置数据的理由与用例依赖、未覆盖项、并发核对一节、已知限制；删去过时的“受限账户验收待补做”；证据链接改为WebXY1124A。sql/week12/README.md、根README同步。未推送。
- 终审（另开AI会话，只读）：对照两份讲义与agent.md检查87d96a7，提出8点（用例未查全部业务表、ROADMAP缺死锁修正、证据链接指向旧批次、证据说明残留“暂存”段、扩展需加参数、第12周报告缺分工、未说明删除订单、ROADMAP第10周旧条目）。肖懿决定“继续改”，第5、8点按AI建议（不改默认安装、旧条目不改原文只追加）。
- 测试脚本：T5补批次与paid_at；R2补审计、actual_amount、completed_at；R4补total_quota、流水、审计；新增R6（status='failed'补货单→53312）。53313在本库不可构造（供应商CHECK四值，trg_W6_ProductsHistory禁止改已引用商品供应商，四个供应商均有被引用商品），新增R7核对此前提，未伪造场景。
- 复测WebXY1124B：app_prepare --with-week10 --with-week11 --with-week12退出0；test_trigger 14/14、test_transactions 14/14、TRANCOUNT=0；test_week11_12_sql 9 OK；全量124 OK；ruff check、format --check通过。启动方式：Win32_Process Create 运行带BOM的脚本，避免SSH断开中止；首次启动命令因PowerShell 5吞掉引号未执行，改为启动脚本后成功。清理-KeepEvidence PASS。
- 文档：README开头写明建库参数及链接改指WebXY1124B；分工表链接改指WebXY1124B；第11周报告补删除订单保护、验证表补S与1124B、覆盖补A7；第12周报告补R6/R7、覆盖范围、分工链接；ROADMAP补死锁修正与终审两节，第10周旧条目下追加说明；R、S证据说明末尾补记已写入AI记录。用户转达的“11-24”按实际日期记为11-23。


## 2026-11-23 第12周商品分类自动维护修正

- **用户人工发现与要求**：阮依成指出第12周 `w12.ProductCategoryAssignments` 只在安装时为已有商品建立映射，Web 后续新增/删除商品时没有自动维护，要求修复，并把本次人工发现与修改同步记录到 AI 使用日志和 AI 使用文档。
- **实现方案**：将维护放在数据库层，避免只在 Web 单一路径维护。商品新增和更新由 `dbo.Products` 的 AFTER INSERT、UPDATE 触发器处理；OpenAI 根据 `token_amount <= 100000` 映射到分类 8，否则分类 9；Claude、Gemini、Other 分别映射到分类 5、6、7。商品删除成功时，由 `w12.ProductCategoryAssignments.product_id` 外键的 `ON DELETE CASCADE` 清除映射。已有订单或调用历史的商品仍受原有历史保护和外键限制，不能绕过规则删除或变更供应商。
- **代码与测试**：
  - 修改 `sql/week12/category.sql`：增加级联删除，并新增 `dbo.trg_W12_ProductCategoryAssignments`，对 inserted 集合执行映射更新和缺失映射补建；原递归函数 `w12.fn_CategoryDescendants` 不变。
  - 新增 `sql/week12/test_category_maintenance.sql`：6 个用例覆盖新增商品、OpenAI 容量跨越 100K、供应商变更为 Claude/Gemini/Other、删除后商品及映射均不存在；通过递归函数连接映射表检查可见性与叶子分类。测试在事务中执行并回滚。
  - 修改 `tests/test_week11_12_sql.py`：增加分类自动维护 SQL 回归与源码检查。
- **验证过程**：源码测试 5 项通过，Ruff 检查与格式检查通过。首批 WebXY1124C 从空库构建成功，分类 6/6、触发器 14/14、事务 14/14；第一次全量 unittest 因构建后未保留 `DB_LAB_DEMO_PASSWORD`，13 项需要该环境变量的员工/Web 集成测试被跳过，未把这次结果作为最终全量验收。随后以同一临时密码变量贯穿构建与测试，在新批次 WebXY1124D 从空库重建并复测：分类 6/6、触发器 14/14、事务 14/14，窗口与递归查询退出码 0；全量 unittest 126 项通过、0 失败、0 错误、0 跳过；`ruff check webapp tests tools` 通过，`ruff format --check webapp tests tools` 显示 38 个文件已格式化。
- **证据与文档**：验证结果保存在 `result/week12/WebXY1124D/`；`README.md`、`sql/week12/README.md`、`report/week12_report.md`、`ROADMAP.md` 同步更新，移除“新建/修改商品不自动维护”的过期描述。触发器日志中的本机 Windows SQL 登录标识已脱敏；A2 用例仍验证 `login_name=ORIGINAL_LOGIN()`。
- **边界**：递归查询函数本身未改；已有历史引用的商品仍不能删除，级联删除仅在商品删除操作本身符合原业务约束时发生。

- **清理**：WebXY1124C、WebXY1124D 均执行 `tools/cleanup_reproduction.ps1 -KeepEvidence` 并核验 PASS，三个测试数据库及对应 SQL 备份删除，证据目录保留；未改动原有演示数据库。


## 2026-11-23 第三阶段旧库与第二阶段文件归档

- **用户要求与责任归属**：阮依成确认自己是本轮第12周商品分类自动维护缺口的人工发现者，要求更新 `docs/team_division.md`；同时清理旧测试数据库、过期的第二阶段展示操作说明，并将第二阶段验收清单、报告等历史阶段文件移入 `archive/`。
- **文档实施**：将 `docs/stage2_acceptance.md`、`docs/stage2_dashboard.md`、`report/stage2_report.md` 移到 `archive/stage2/`，按新文件位置重算内部链接，修正 README、团队分工、计划与多份历史证据索引中的指向；仅删除用户指定的旧展示操作文档及其关联的过期导航段落。两份当前 AI 记录按用户要求清理仅涉及旧展示流程编排的记录；其余技术实施、故障修复和验收历史保留，不改变 Git 既有历史。
- **数据库清理方案**：先只读查询 `sys.databases` 和当前 SQL 用户会话，清单精确匹配本机 45 个 `TokenHubDB` 实例数据库；明确保留原始 `TokenHubDB_v01_A`、`TokenHubDB_v11_WebManualA01`、`TokenHubDB_v11_WebFinal1106A`、`TokenHubDB_v11_WebEmp26A01`、`TokenHubDB_v11_WebStage2A02`，其余40个旧复现/测试库按名执行 DROP，逐个核验不存在。结束后数据库列表恰好等于5个保护项；没有强行断开正在使用的 SQL 连接，没有删除已有 Git 证据和外部 SQL 备份，具体名单见 `archive/stage2/database_cleanup_20261123.json`。
- **分工记录**：增补阮依成在第12周人工检查中指出“新增/修改/删除商品不自动维护分类映射”的问题，提出修复与文档同步要求；由 AI 辅助修改 SQL、增加专项测试及自动执行，不将脚本执行冒称其本人手动操作。结果使用 WebXY1124D 的分类6/6、触发器14/14、事务14/14、全量126/126历史记录。
- **验证与后续**：需以项目目录的链接检查、`git diff --check`、已删数据库与保留白名单、分工条目存在性及当前第10—12周入口保留为收尾条件。旧库删除后如需复跑应以全新后缀建隔离库，不使用已删库名直接启动应用。

## 2026-11-23 第三阶段交付入口精简

- **用户要求**：助教接下来只验收第10周及以后，要求根README不再列第5—9周成果；旧AI记录、分工、三份旧计划和历史ROADMAP移入归档。阮依成进一步确认陈诗翰负责第10周，第12周人工发现的商品分类维护缺口应简要写在本人对应分工行，不需要单列长段落。
- **实施**：完整保留第5—9周及Web历史过程于 `archive/stage2/`；活动 `README.md`、`ROADMAP.md`、`docs/ai_usage_log.md`、`docs/ai使用文档.md`、`docs/team_division.md` 从第10周起组织。新分工表四行：陈诗翰负责第10周及第11周窗口/测试，阮依成负责第12周分类与事务证据核对（包括人工发现分类映射缺口），肖懿负责第11—12周其余实现及验收。未继承原文“据转告已审阅确认”的不充分声明。
- **第10周新增表核查**：实际新增 `w10.InventoryAdjustments` 库存校正表，用于记录调整原因、员工、校正前后额度及操作键，`log_id` 关联原有 `dbo.InventoryLog`；第10周增量由18表22FK变成19表26FK。该记录有业务及幂等作用，不作为冗余表删除。
- **收尾**：Markdown链接验证通过，归档保留历史资料而不影响 SQL/Web 构建依赖；当前项目未执行新的数据库写入测试。原名 `.stage3_cleanup_once.py`、`.stage3_db_cleanup_once.py` 已不存在，临时整理脚本用后清理。

## 2026-11-25 第13周实施与双会话回归

- **需求与取舍**：用户要求按仓库推进第13周。直接用库存简表可精确复现 10/8、13/15；直接修改业务库存扣减时机则会影响支付、模拟调用和退款口径。采用简化 P/Q SQL 观察锁，并在实际事务验证固定顺序及可售余量竞争。未新增前端入口。
- **反例和修正**：WebW13Run01 从空库安装旧事务，共用入口锁检查返回 57114。先调整补货夹具必填字段，再处理死锁捕获时的不可提交事务、增量脚本会话选项和 ODBC 参数批次的外层事务计数。竞购试跑记录 B 先在余额索引 RangeS-U 等待，随后改为先取供应商入口锁，再取原余额与库存行锁。中间输出保留在 `result/week13/WebW13Run01/`；中间版 WebW13Run02 全量126项通过。
- **采用**：在 `sql/week12/install.sql` 接入 `sql/week13/provider_lock.sql`，修改支付和补货事务各自的取锁链路。用 `tools/week13_verify.py` 重放 A/B 脚本，观察第三连接的 DMV 锁和等待数据。同一可售余量 10 份只允许一笔6份订单完成，另一笔返回53132且不发放余额、批次。
- **核验和证据**：WebW13Run03 以三周参数构建，`unittest discover -s tests` 126项通过、0跳过，双会话脚本通过；独立复跑触发器14/14、事务14/14、分类6/6，窗口和递归查询退出0。用 `-KeepEvidence -WhatIf` 后执行正式清理，三个本轮批次均核验通过。[复现证据](../result/week13/WebW13Run03/README.md)；RCSI 在本轮关闭，未改共享配置。未登记独立组员复现。

### 第13周审查修复

- 用户要求修复只读审查发现的三项问题。先在专用 WebW13Fix01 库运行 `tests/test_week13_sql.py`：复现别名申请不同应用锁、手工脚本在 1222 后提交后续写入，以及 Web 补货返回 503。
- 在 `sql/week13/provider_lock.sql` 使用数据库比较规则映射固定锁名，单次获取等待改为 10 秒；相关 A/B 写入步骤捕获错误后整体回滚，后续步骤校验前段事务存在。未修改余额、库存扣减时机或 Web 超时配置。
- 专项复跑 3 项通过，包含第二个键超时后撤销第一笔写入；Web 补货返回 409，库存、补货单、流水和审计不变。原双会话重放与第12周事务 14/14 通过。证据见 [WebW13Fix01](../result/week13/WebW13Fix01/README.md)；未将此轮记为全量回归或组员独立验收。
