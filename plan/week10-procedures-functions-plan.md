# 第10周存储过程与函数执行计划

> **For agentic workers:** 使用 superpowers:executing-plans 按任务实施并核对检查项，所有工作直接在原项目中进行。

**Goal** 完成第10周要求的销售统计、库存调整、补货量、销售汇总及折扣计算，并整合现有Web入口，保存逐项正反例结果。

**Architecture** 在当前v1.1与Web基线上增加 `w10` 数据库对象及受控应用入口。SQL Server执行计算与业务写入，Flask负责路由、身份、输入格式检查和参数绑定。支付、调用、FIFO与退款复用现有交易机制。

**Tech Stack** SQL Server、T-SQL、SQLCMD、Flask、Jinja、原生JavaScript、pyodbc、unittest、Ruff、现有Edge自动化工具。

计划日期为2026-11-11，审查基线为 `afbcf54d3403d2492a031cd977cbf9c0a7c2826a`。读取前工作区干净，以下实施项均待执行。

## 1. 当前上下文

- 正式目录为 `D:\Desktop\DB\DB_lab`，协作约定见 [AGENT.md](../AGENT.md)。
- 第5—9周已完成规范化迁移、内部v1.1账务、四层Web、顾客注册、管理员工、受限Windows账户部署和跨机器复现。早期对话中“没有注册功能”的描述已过期。
- 当前为17张业务表与 `app.Sessions`。库存按 `Inventory.account_id` 管理，与上游账号一一配对。商品通过 `model_provider` 对应上游供应商。
- 下单保存快照，支付发放余额与Token批次，调用扣上游库存，退款按明细 `subtotal` 和未消费批次比例计算。
- 已有SQL过程覆盖订单创建/合并、支付、调用、补货、退款。本周扩展这些入口，页面取数据库计算结果。
- 最新完整测试记录为 [WebFinal1106A](../result/stage2/WebFinal1106A/README.md) 的75项通过。受限Windows账户验收见 [WebXY1105F](../result/stage2/WebXY1105F/README.md)。本轮仅读取上述记录与源码。
- 当前构建依赖 `sql/v01`、`sql/v10`、`sql/v11`、`db_tools/v11` 和 `sql/app`，新增内容接在 `tools/app_prepare.py` 的应用安装之后。

## 2. 第10周要求映射

来源为 `D:\Desktop\第10周任务讲解.docx`，包含第三阶段总览与第10周详细任务。

| 课程要求 | 本项目对象/交付 | 核验内容 |
|---|---|---|
| 日期区间销售统计过程 | `w10.usp_SalesStatistics` | 订单数、套餐件数、成交额、商品明细与空结果 |
| 商品库存调整过程 | `w10.usp_AdjustInventory` | 商品/账号匹配、正负调整、流水与回滚 |
| 补货量函数 | `w10.fn_ReplenishmentQuantity` | 当前/最低/目标库存、缺失商品与非负结果 |
| 销售汇总表值函数 | `w10.fn_SalesSummary` | SELECT调用，商品编号/名称/销量/金额/订单数 |
| 折扣函数和历史成交记录 | `w10.fn_OrderDiscount`、明细快照增量 | 阈值、舍入、草稿重算、支付冻结与折后退款 |
| 业务整合 | SQL应用入口、API和页面 | 数据库计算，页面调用，受限身份执行 |
| 调用与结果记录 | `call_examples.sql`、`regression.sql`、集成测试 | 输入、预期、实际、错误、数据前后对账 |

第11周触发器与窗口查询、第12周递归与事务专项、第13周锁等待/隔离/死锁专项另行细化。本周覆盖新增操作必要的原子性与并发保护。

## 3. 业务口径与建议决策

本节为计划建议。金额折扣阶梯、管理员库存校正权限、补货默认值与销售统计口径尚待审核。

### 3.1 销售统计

- 输入 `@start_date DATE`、`@end_date DATE`，包含首尾两天，使用Asia/Shanghai时间。查询条件为开始日零点起、结束日次日零点前。结束日为9999-12-31时使用无上界分支，避免日期溢出。
- 过程拒绝NULL与倒置日期。非法DATE文本由SQL Server参数类型转换拒绝，HTTP入口检查ISO日期格式。
- 统计 `paid_at` 非空且状态为 `paid/refunded` 的成交订单，使用历史折后 `subtotal`。退款订单保留原成交额，页面标注“成交额（含后续退款订单）”。
- 销量为套餐件数 `SUM(quantity)`。Token销量如展示则单独命名，订单数去重，跨商品总订单数从订单集合直接计算。
- TVF每个有成交的商品一行，无记录返回空表。过程固定返回一行总览与一个商品明细结果集，空区间总览返回0。
- 金额聚合使用 `DECIMAL(38,2)`，计数使用BIGINT。过程以同一次读取物化成交明细，再计算总览及商品汇总，避免两结果集读取不同现场。
- TVF无法THROW，NULL/倒置日期返回空表。过程先校验并抛业务错误，直接SELECT调用文档明确此约定。

### 3.2 商品与账号库存适配

- 过程参数为 `@product_id INT`、`@account_id INT`、`@change_amount BIGINT`、`@reason NVARCHAR(255)`、`@operator_id INT`、`@operation_key UNIQUEIDENTIFIER`。数量单位为上游Token。
- 校验商品与账号存在且供应商匹配、账号当前有效可操作、员工有效且为管理员、原因非空且未超长、调整量非零、配对库存存在且账务一致。
- 建议人工校正仅管理员可用，店员沿用补货流程。Web入口从会话取得员工编号，SQL应用入口再次验证身份。
- 调整同时令 `total_quota += delta`、`current_quota += delta`，`used_quota`保留历史消费值。用宽精度中间计算防溢出，包括BIGINT最小负值。
- 调整后 `current_quota >= 0`、`total_quota > 0`、`total_quota >= used_quota`，且 `current_quota = total_quota-used_quota`。used为0且调整使total为0时按既有约束拒绝。
- 同一事务写入 `InventoryLog(change_type='adjustment', reference_type='manual', reference_id=NULL)` 与 `w10.InventoryAdjustments`。新表保存商品、账号、员工、原因、数量、前后库存/总额度、关联log_id、操作键和时间。
- 现有 `trg_W6_InventoryTypedRefs` 禁止manual流水带非空reference_id，调整表以外键关联流水。运行期间保持原保护触发器启用。
- 操作键唯一，同键同参数返回已有结果，同键不同参数报冲突，不同键表示不同校正。操作键与HTTP请求编号分别承担重放控制和日志定位职责。
- 账号和库存使用更新锁与范围锁，固定锁顺序并对照调用/补货入口。失败整体回滚，四张相关表无部分变更。

### 3.3 补货量函数

- 签名为 `w10.fn_ReplenishmentQuantity(@product_id INT, @account_id INT, @minimum_quota BIGINT, @target_quota BIGINT) RETURNS BIGINT`。
- 最低量为NULL时取账号 `safety_threshold`，目标量由调用方输入。目标量应大于等于最低量，二者非负。
- 当前量低于最低量时返回 `MAX(目标量-当前量,0)`，否则返回0。
- 商品/账号缺失、跨供应商、账号无效、配对不一致或非法参数返回NULL。包装过程将NULL映射为明确业务错误，直接SELECT示例说明NULL含义。
- 建议量取函数本次读取的库存，创建任务由员工确认，实际完成仍在事务内检查当前状态。

### 3.4 折扣计算与历史兼容

- 课程允许按会员身份、金额或分类计算，建议采用金额规则。原价合计小于100元折扣率0，达到100元为0.05，达到500元为0.10，取最高一档。
- 内联TVF `w10.fn_OrderDiscount(@gross_amount DECIMAL(18,2))` 返回折扣率与试算优惠额。NULL/负值返回空表，由过程报错，0元返回0折扣。
- `OrderDetails` 新增 `original_subtotal DECIMAL(10,2)`、`discount_rate DECIMAL(5,4)`、`discount_amount DECIMAL(10,2)`、`pricing_rule_version VARCHAR(32)`。`unit_price`继续保存首次单价，`subtotal`保存折后小计。
- 旧明细回填原小计、0折扣和 `legacy` 版本。先验证旧明细等式，发现不一致即中止。迁移前后对账旧金额、Token、批次与退款。
- `trg_W5_NoEditFinalizedDetails` 会拒绝已成交明细更新，部署需在明确的迁移事务内处理回填及触发器恢复，并验证失败恢复保护。常态入口继续禁止修改历史明细。
- 旧草稿继续legacy规则。新订单采用 `amount-v1`，加/改/删明细后按原价合计确定统一折扣率，每行优惠 `ROUND(original_subtotal*discount_rate,2)`，小计为原价减优惠，订单金额取小计之和。
- 订单优惠额取逐行优惠之和，函数对订单原价的试算值可能因舍入存在分位差异。页面显示保存后的逐行合计。
- 支付锁定并核验快照后沿用现有支付过程发放Token，折扣不改变Token数量。退款继续以折后subtotal为基数。
- 前端不能指定折扣率、成交价或规则版本。适配过程保留旧参数、默认值、OUTPUT与 `@emit_result` 约定。

## 4. 文件布局

| 新增文件 | 职责 |
|---|---|
| `sql/week10/schema.sql` | 新schema、调整表、折扣列、回填与约束 |
| `sql/week10/function.sql` | 三个函数 |
| `sql/week10/procedure.sql` | 销售统计、库存调整、内部草稿重算 |
| `sql/week10/app_adapters.sql` | 新版本定价接入现有订单/明细/支付入口 |
| `sql/week10/install.sql` | SQLCMD参数、目标保护和顺序安装 |
| `sql/week10/call_examples.sql`、`regression.sql` | 调用、正反例和断言 |
| `sql/week10/README.md` | 参数、返回、错误、口径和运行说明 |
| `sql/app/week10.sql` | `app.Week10` 会话授权及受控JSON入口 |
| `tools/week10_verify.py` | 逐例预期/实际与四表/账务核验 |
| `tests/test_week10_sql.py`、`test_week10_web.py` | SQL与HTTP测试 |
| `tools/week10_browser.py` | 新页面Edge流程及截图 |
| `report/week10_report.md` | 第10周对象、运行结果与分析 |

修改 `tools/app_prepare.py` 增加显式 `--with-week10`，保持现有默认构建可复现。修改 `webapp/dao.py`、`services.py`、`__init__.py`、`errors.py` 增加调用、角色、输入和错误映射。页面修改集中在现有模板、app.js和app.css。

同步根README、SQL索引、数据字典、可编辑ER及渲染结果、ROADMAP和AI记录。新增一张调整表后预计19张表，外键数量以实际系统目录查询为准。证据写入 `result/week10/<RunId>/`。

## 5. 分步任务与提交

每个有意义的修改步骤完成后立即同步ROADMAP及两份AI记录。按用户要求逐项本地commit，提交前检查差异与验证输出。

### P0 基线和安装入口

- [ ] 记录Git状态、提交号、工具版本、SQL服务、端口及目标库是否存在。
- [ ] 用从未使用过的后缀 `WebW10Base01` 运行现有准备流程，执行完整unittest并保存实际通过/失败/跳过数。
- [ ] 为 `--with-week10` 编写参数解析和前置拒绝测试，再接入安装入口与manifest中的扩展版本/对象清单。
- [ ] 使用新后缀 `WebW10Dev01` 验证开发安装，拒绝非允许的隔离Web库、缺前置对象和重复安装。
- [ ] 提交 `build(week10): add opt-in week10 preparation entry`。

### P1 结构和兼容迁移

- [ ] 为旧订单、明细、Token批次、退款、库存生成迁移前对账基准。
- [ ] 编写schema增量与旧快照回填，验证默认值、外键、操作键唯一及金额约束。
- [ ] 覆盖已成交明细回填触发器冲突和部署失败，断言旧值一致、约束可信、触发器恢复启用。
- [ ] 验证空草稿、已有明细草稿、已退款订单、注册及员工管理仍可使用。
- [ ] 提交 `feat(week10): add pricing snapshots and adjustment ledger`。

### P2 函数和销售过程

- [ ] 实现补货标量函数、销售TVF、折扣TVF，再实现销售统计过程。
- [ ] 写出三个函数的直接SELECT例子与过程参数化调用，样例ID从本轮夹具捕获。
- [ ] 将第6节的日期、空结果、阶梯、NULL、错误ID、大数预期逐项写成断言并运行。
- [ ] 验证销售过程两组结果一致，总订单数不会因多商品重复计数。
- [ ] 提交 `feat(week10): add sales and replenishment functions`。

### P3 库存调整事务

- [ ] 完成输入、角色、供应商、账号有效性、额度范围与操作键校验。
- [ ] 按固定锁顺序更新账号、库存、流水和调整记录，返回调整前后值。
- [ ] 注入流水/调整表写入失败，逐表比较快照，确认整体回滚。
- [ ] 两连接测试同键重放和负向校正，断言无重复调整和负库存，流水差额匹配。
- [ ] 提交 `feat(week10): add audited atomic inventory adjustment`。

### P4 折扣接入订单

- [ ] 实现内部草稿重算过程，接入创建、合并、改数量、删明细入口。
- [ ] 按订单版本处理legacy和amount-v1，保留首次单价快照及旧结果集契约。
- [ ] 支付前校验金额和Token等式，再调用原支付过程，不在支付时回写已冻结明细。
- [ ] 运行折后支付/消费/部分退款、商品改价和并发重复支付，验证账务一致。
- [ ] 注入重算、支付批次及退款失败，确认回滚后不继续使用失效事务。
- [ ] 提交 `feat(week10): persist SQL-calculated order discounts`。

### P5 API与受限权限

- [ ] 实现 `app.Week10`，会话解析后进行SQL角色检查，仅向app_runtime授予此入口EXECUTE。
- [ ] 新增 `GET /api/v1/reports/sales`，店员/管理员可查。
- [ ] 新增 `GET /api/v1/restocks/recommendation`，店员/管理员提交商品、账号、最低量和目标量。
- [ ] 新增 `POST /api/v1/inventory/adjustments` 及管理员只读记录查询，员工来自会话。
- [ ] DAO统一将销售件数、订单数、建议量、调整数量/前后值及金额/比例转为约定字符串。
- [ ] 新SQL业务错误使用稳定56xxx编号，映射400/401/403/404/409，数据库不可用503，响应保留统一JSON和请求编号。
- [ ] 验证伪造员工/折扣、顾客看销售、店员校正库存与直接执行内部过程被拒绝，旧API与CSRF回归通过。
- [ ] 提交 `feat(api): expose week10 database operations`。

### P6 页面整合

- [ ] 增加销售统计页，展示日期、总览、商品明细和空状态。
- [ ] 库存页增加管理员有符号数量校正表单与前后值记录，原因必填。
- [ ] 补货页增加建议量计算和创建任务确认，完成任务沿用现有入口。
- [ ] 订单详情展示原价、折扣率、优惠与应付额，全部取接口值。
- [ ] 请求期间禁用按钮，同次校正重用操作键，成功完成或明确新建操作后换键。
- [ ] Edge验证新增页面，截图前等待数据完成并断言列名、编号和金额。
- [ ] 提交 `feat(web): add sales inventory and discount views`。

### P7 最终验证

- [ ] 使用新后缀 `WebW10Final01` 从空库重建。先完成原v1.1固定样例回归，再安装第10周扩展。
- [ ] 安装顺序为schema、function、procedure、app_adapters、app/week10，验证所有前置对象与版本。
- [ ] 全量运行原75项与新增测试，旧金额预期明确绑定legacy夹具或对应规则版本。
- [ ] 每例保存输入、预期、实际、异常号、对象前后值和PASS/FAIL/SKIP。
- [ ] Edge复测注册、员工管理、支付/调用/退款、补货与新增页面，保存截图及请求编号。
- [ ] 以专用普通Windows身份实际验证入口成功、越权拒绝、基表访问/DDL/内部过程执行拒绝。
- [ ] 记录启动方式、库名、提交号、身份与端口，验收结束停止对应服务并核验端口释放。
- [ ] 提交 `test(week10): verify functions workflows and runtime permissions`。

### P8 交付文档

- [ ] 编写周次SQL说明和报告，说明过程/函数区别、业务口径、错误和实际结果。
- [ ] 更新数据字典、可编辑ER与SVG/PNG，核对字段、实体及外键。
- [ ] README补充安装、启动、角色操作、函数SELECT与测试入口及关闭服务步骤。
- [ ] 核对任务映射、相对链接、AI记录与实际结果，成员分工按实际确认登记。
- [ ] 提交 `docs(week10): document procedures functions and acceptance results`。

## 6. 必须落实的测试预期

每个测试使用本轮创建记录的OUTPUT编号，不依赖旧固定ID。

| 分类 | 输入/现场 | 预期 |
|---|---|---|
| 多商品销售 | 同一天订单一P两件单价30、Q一件40，订单二P一件30 | 新规则订单一优惠5、实付95，订单二实付30；总订单2、件数4、金额125；P三件金额87、订单2；Q一件金额38、订单1 |
| 状态口径 | 增加pending/cancelled单，之后退款订单一 | 待支付/取消排除，成交额仍125 |
| 日期边界 | 开始日00:00、结束日23:59:59、次日00:00支付 | 前两项计入，次日排除，按paid_at统计 |
| 空/非法日期 | 无成交、NULL、倒置、结束日9999-12-31 | 空总览0/明细空，NULL/倒置过程报错，最大结束日可查 |
| 补货 | current100、minimum200、target1000 | 返回900 |
| 补货零值 | current200或1000、minimum200、target1000 | 返回0 |
| 补货非法 | 错商品/账号、跨供应商、target<minimum、目标NULL、负阈值 | UDF为NULL，API明确错误，无写入 |
| 校正正负 | total1200、used200、current1000，先+300再-400 | total1500/1100，current1300/900，used200，两条匹配流水和调整记录 |
| 校正不足 | 上例current900，再-901 | 拒绝，四表不变 |
| 校正非法 | NULL/0数量、BIGINT上下界、空/超长原因、错误员工、失效账号 | 明确失败，无部分记录和静默截断 |
| 校正重放 | 同键同参两次，同键改数量 | 同参返回原记录只调整一次，改参报冲突 |
| 折扣阶梯 | 原价99.99、100、499.99、500 | 优惠0、5、25、50，净额99.99、95、474.99、450 |
| 逐行舍入 | 两行0.10和99.90 | 行优惠0.01/5.00，总优惠5.01、净额94.99 |
| 草稿重算 | 原价90增至120再删回90 | 优惠0/6/0，实付90/114/90，首次单价不变 |
| 折后部分退款 | 单行原价200、发行200000、消费50000 | 实付190，回收150000、退款142.50，余额/批次/退款一致 |
| 历史兼容 | 升级前paid/refunded与旧草稿，升级后新单 | 旧值一致，新单采用amount-v1 |
| 非法折扣 | 函数NULL/负原价，前端传负折扣、>1折扣或成交价 | 函数空结果/过程报错，前端伪造拒绝 |
| 重复交易 | 同单再支付、同任务再完成、同单再退款 | 支付/补货冲突且不重复记账，退款返回原结果 |
| 回滚并发 | 流水、批次、退款中途失败，并发负校正 | 无部分提交、重复充值和负库存/余额 |
| 权限 | 游客/顾客查销售、店员校正、伪造员工、直写基表 | HTTP或SQL明确拒绝，角色与数据不变 |

## 7. 运行与验收命令

在原项目根目录执行。后缀每次换新，密码通过环境变量输入。

```powershell
$env:DB_LAB_DEMO_PASSWORD = Read-Host '输入本轮实验密码'
.\.venv\Scripts\python.exe tools/app_prepare.py --suffix WebW10Base01
$env:DB_LAB_APP_DATABASE = 'TokenHubDB_v11_WebW10Base01'
$env:DB_LAB_TEST_DATABASE = 'TokenHubDB_v01_WebW10Base01'
$env:DB_LAB_PREVIEW = '1'
$env:DB_LAB_SECRET = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

实施新增安装选项后，新库构建命令为下面一行。

```powershell
.\.venv\Scripts\python.exe tools/app_prepare.py --suffix WebW10Final01 --with-week10
```

验收时将环境变量切换到本次专用新库，设置对应实验密码，再执行以下检查。

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -p 'test_week10*.py' -v
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\.venv\Scripts\ruff.exe check webapp tools tests report/render_app_er.py
.\.venv\Scripts\ruff.exe format --check webapp tools tests report/render_app_er.py
sqlcmd -S 'localhost\SQLEXPRESS' -E -C -b -f 65001 `
  -d $env:DB_LAB_APP_DATABASE -v "DatabaseName=$env:DB_LAB_APP_DATABASE" `
  -i sql/week10/regression.sql
git diff --check
```

SQL脚本使用断言与THROW使失败退出码非零。预期错误在TRY/CATCH中核验异常号，意外成功必须失败。测试以实际发现数量、OK和零非预期跳过为验收依据，数据库未运行则记为skipped或blocked。失败证据保留在独立尝试目录。

## 8. 完成条件

- [ ] 两个必需过程与三个函数参数、结果和异常处理明确，SELECT与EXEC示例可复现。
- [ ] 日期、空结果、非法编号/数量/折扣、重复调用和回滚均有实际断言结果。
- [ ] 历史金额与Token保持迁移基准，新订单折扣、支付和退款账一致。
- [ ] 新库全量回归、Ruff、页面流程及普通Windows身份权限验证通过。
- [ ] README含启动和验收后关闭步骤，服务结束后核验端口释放。
- [ ] 数据字典、ER、报告、任务映射、ROADMAP与AI记录一致，每项变更本地提交。

待审核的业务建议为金额阶梯折扣、管理员专属校正、最低量默认安全阈值与成交额包含后续退款订单的口径。规则变更时同步本计划、SQL断言和页面文案。
