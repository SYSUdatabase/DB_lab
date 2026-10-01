# DB_lab v0.1 复现与验证说明

本文档说明如何从空库完整复现 v0.1，以及如何核对复现结果。所有结论都来自 SQL Server 的真实执行输出，不依赖本文档的描述。

## 1. 环境要求

```powershell
sqlcmd -S 'localhost\SQLEXPRESS' -E -C -b -Q "SELECT @@VERSION;"
```

- SQL Server 2025 Express（Developer Edition，17.0.1000.7）
- Windows PowerShell 5.1
- 使用 Windows 集成认证（`-E`），不需要保存 SQL 登录密码

## 2. 一键从空库复现

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_v01.ps1 `
  -DatabaseName TokenHubDB_v01_A -RunLabel run_A
```

脚本按固定顺序执行，并在每一步检查退出码：

```text
PASS 00_create_database.sql
PASS 01_create_tables.sql
PASS 02_insert_data.sql
PASS 03_crud_demo.sql
PASS view.sql
PASS query.sql
PASS constraint.sql
PASS role.sql
PASS verify.sql
PASS signature.sql
PASS v0.1 TokenHubDB_v01_A
```

> **如果脚本报 `TokenHubDB_v01_A already exists. Reproduction requires an empty database.`**
>
> 目标库已存在，脚本**拒绝覆盖**——这是有意的保护，避免删掉已有数据或证据库。请二选一：
>
> ```powershell
> # 选 1（推荐）：换一个新库名，保留现有库
> powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_v01.ps1 `
>   -DatabaseName TokenHubDB_v01_D -RunLabel run_D
>
> # 选 2：明确要求删除同名库后重建（只作用于 TokenHubDB_v01_* 实验库）
> powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_v01.ps1 `
>   -DatabaseName TokenHubDB_v01_A -RunLabel run_D -DropExisting
> ```
>
> 选 2 会删掉同名库。如果该库是 `result/screenshots/` 里截图的证据来源（本项目当前 A 库就是），删掉后那些截图就没有对应数据库了，`result/evidence_logs/` 中的日志仍会保留。日常复现建议用选 1。
>
> 上面命令块里默认示例用的 `TokenHubDB_v01_A` 在本项目已被占用，直接照抄会中止；请按实际情况替换库名。

常用参数：

| 参数 | 作用 |
|---|---|
| `-DatabaseName` | 目标实验库名，仅允许 `TokenHubDB_*` 前缀；库已存在时报错中止，不覆盖 |
| `-RunLabel` | 结果输出目录名，默认 `run_A`；同名目录已存在时脚本拒绝覆盖，需换标签或先删目录 |
| `-DropExisting` | 先删除同名实验库再重建；不加该参数时绝不自动删库 |

失败时 `result/<RunLabel>/console.log` 和对应的 `<脚本名>.log` 会记录原因。常见两类：

| 报错 | 原因 | 处理 |
|---|---|---|
| `TokenHubDB_xxx already exists. Reproduction requires an empty database.` | 目标库已存在 | 换 `-DatabaseName`（推荐），或加 `-DropExisting` |
| `Result directory already exists; choose a new RunLabel: xxx` | `result/<RunLabel>/` 已存在 | 换 `-RunLabel`，或先删除该目录 |

两条保护都不提供"默认强制覆盖"，避免误删证据库或历史日志。

## 3. 三个空库的内容一致性

`result/run_A/`、`result/run_B/`、`result/run_C/` 是三次独立复现的输出目录。`signature.sql` 对 14 张表逐表计算完整内容的 SHA-256：

```powershell
Compare-Object `
  (Get-Content .\result\run_A\signature.txt) `
  (Get-Content .\result\run_B\signature.txt)
```

预期无输出。三个 `signature.txt` 均为 14 行、1129 字节且逐字节一致，说明脚本是确定性的，重复执行不会改变基础业务数据。

## 4. 主要验证项与预期值

| 验证项 | 位置 | 预期结果 |
|---|---|---|
| 业务表数量 | `sys.tables` | 14 张用户表 |
| 视图数量 | `sys.views` | 10 个（4 个经营统计 + 6 个权限用途） |
| 数据库角色 | `sys.database_principals` | `hub_manager`、`hub_staff`、`hub_customer`、`hub_guest` |
| 订单明细行数 | Q01 | 184 |
| 已支付订单 / 销售额 / Token | Q02 | 85 单 / 4228.90 / 92950000 |
| 无已支付订单的会员数 | Q05 | 14 |
| 低库存边界判定 | Q09 | 事务内命中 3 行（1 行为临时账号），随后回滚并断言 `@@TRANCOUNT=0` |
| 连接方式对照 | Q10 | 会员 26 行（INNER JOIN）vs 40 行（LEFT JOIN） |
| 用量趋势 | Q11 | `UsageSummary` 按日、按月两种粒度 |
| 上游账号消耗排名 | Q12 | `InventoryLog` 的 `consumption` 变动净额 |
| 完整性用例 | C01～C14 | 合法用例回滚；非法用例的实际错误号与约束名必须与预期一致 |
| 权限用例 | R01～R17 | 访客/店员/会员/店长的允许与禁止操作逐条比对 |
| 综合验收 | VFY01～VFY11 | 订单、库存、余额、汇总粒度的逐行与逐键对账 |

## 5. 验收日志

`result/run_A/verify.sql.log` 末尾：

```text
PASS VFY07 product view row-by-row
PASS VFY08 member view row-by-row
PASS VFY09 balance reconciliation
PASS VFY10 usage summary reconciliation
PASS VFY11 boundary positives
PASS v0.1 verification
```

`verify.sql.log` 中会出现一条提示 `比较集合时 SET 方法忽略了 Null 值`：验收语句使用 `EXCEPT` / `INTERSECT` 做双向比对，而该语义本身忽略 NULL，属于预期行为，不影响 PASS 结论。

## 6. 关键设计理由

- 金额用 `DECIMAL`，避免 `FLOAT` 近似误差。
- 中文业务文本用 `NVARCHAR`，时间戳用 `DATETIME2(0)`。
- `Inventory` 关联 `UpstreamAccount`：库存表示上游账号可用 Token，不是商品件数。
- `Orders` 与 `OrderDetails` 都保存 Token 汇总属于受控冗余，`verify.sql` 校验两者一致。
- 商品销售只统计 `status = 'paid'`，退款、取消、待支付不计入销售额。
- 会员个人视图用 `USER_NAME()` 绑定数据库用户，不依赖调用者可任意设置的会话变量。
- 店员联系客户走 `v_CustomerService`，视图中不出现 `password_hash`。
- 库存视图把账号可用性（`account_state`）与额度水位（`stock_state`）分开，避免账号过期把低库存显示成过期。
- 库存视图与查询脚本共用同一固定快照时间 `2026-09-22 23:59:59`，避免不同运行日期导致结果漂移。

## 7. 证据位置

| 证据 | 位置 |
|---|---|
| 完整复现日志与签名 | `result/run_A/`、`result/run_B/`、`result/run_C/` |
| 结果截图与说明 | `result/screenshots/`、`result/README.md` |
| 截图对应的证据 SQL | `result/evidence_sql/` |
| 截图对应的原始输出 | `result/evidence_logs/` |
| 第三周人工测试记录 | `result/第3周人工测试演示结果.pdf` |
| 阶段报告 | `report/stage_report.md` |
| 角色权限流程图 | `report/role_workflow.md` |
| 实体关系图与知识导图 | `report/stage_report.md` 第 1 节第 4、7 小节 |
| AI 使用记录 | `ai_usage_log.md` |
| 分工记录 | `team_division.md` |

截图必须来自真实执行。如果某项结论只有日志证据而没有截图，应如实标注，不使用模拟图片代替。当前 `result/screenshots/` 的 22 张 PNG 全部来自 `tools/capture_evidence.ps1` 对 `result/evidence_sql/` 的实时执行，可用 `result/evidence_logs/` 中同名原始输出逐项核对。

## 8. 安全注意事项

- 只操作本项目的实验库，不触碰其他数据库。
- 仓库数据中的 API Key 均为 `DEMO_NOT_A_REAL_API_KEY_*` 占位符，不要放入真实密钥、密码或私钥。
- 执行 `UPDATE` / `DELETE` 前确认 `WHERE` 条件。
- 一键脚本默认不删除任何数据库，只有显式传入 `-DropExisting` 时才会删除 `TokenHubDB_v01_*` 实验库。