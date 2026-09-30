# DB_lab v0.1 复现与课堂演示指南

> 适用：组员复现、课堂展示、助教验收。所有命令均从仓库根目录执行。

## 1. 演示前检查

```powershell
python --version
Get-Command sqlcmd
sqlcmd -S 'localhost\SQLEXPRESS' -E -C -b -Q "SELECT @@VERSION;"
```

确认根目录存在 `sql/`、`tools/run_v01.ps1`、`result/`、`week4/`。

正式实验库建议使用 `TokenHubDB_v01_A`。如果数据库已存在，不要直接覆盖；需要重新演示空库复现时，只删除本项目实验库。

## 2. 一键从空库复现

```powershell
powershell -NoProfile -File .\tools\run_v01.ps1 `
  -DatabaseName TokenHubDB_v01_A -RunLabel demo_A
```

预期依次看到：

```text
PASS 00_create_database.sql
PASS 01_create_tables.sql
PASS 02_insert_data.sql
PASS 03_crud_demo.sql
PASS query.sql
PASS view.sql
PASS constraint.sql
PASS role.sql
PASS verify.sql
PASS signature.sql
PASS v0.1 TokenHubDB_v01_A
```

## 3. 10 分钟课堂演示顺序

### 第 1 分钟：建库与 14 张表
在 SSMS 连接 `localhost\SQLEXPRESS`，打开 `TokenHubDB_v01_A`。

```sql
USE TokenHubDB_v01_A;
SELECT COUNT(*) AS table_count FROM sys.tables WHERE is_ms_shipped=0;
```

预期 `table_count = 14`。说明根目录 00～03 是第三周基线，第四周在此基础上新增查询、视图、约束和权限。

### 第 2 分钟：CRUD
打开 `sql/03_crud_demo.sql`，展示 Products、Inventory、Orders 三组 INSERT / SELECT / UPDATE / DELETE。强调演示事务最终回滚，不改变基础数据。

### 第 3～4 分钟：Q01 / Q02 / Q05
打开 `sql/query.sql`：
- Q01：Orders + Users + OrderDetails + Products，184 条订单明细。
- Q02：已支付商品销量，10 个商品，总件数 191，总销售额 4228.90。
- Q05：`NOT EXISTS` 找出 14 个没有已支付订单的会员。

说明 Q02 使用 LEFT JOIN 保留零销量商品；订单总额不能在一对多明细连接后直接重复求和。

### 第 5 分钟：四个核心统计视图
展示：
- `v_OrderDetail`：184 行
- `v_ProductSales`：10 行
- `v_MemberSpending`：40 行
- `v_InventoryStatus`：8 行

库存视图使用固定样例快照时间 `2026-09-22 23:59:59`，避免演示日期变化导致结果漂移。

### 第 6 分钟：约束正反例
打开 `sql/constraint.sql`，重点展示：
- C06：负价格被 `CK_Products_price` 拒绝，错误 547。
- C08：篡改订单明细 subtotal 被 `CK_OrderDetails_subtotal_formula` 拒绝，错误 547。
- C01/C02：合法数据能使用 DEFAULT，并在事务中回滚。

脚本总共执行 C01～C11，只有实际错误号与预期一致才算 PASS。

### 第 7～8 分钟：角色和会员隔离
打开 `sql/role.sql`：
- R04：店员直接修改 Products 被拒绝，错误 229。
- R05：店员可通过 `v_StaffOrderQueue` 处理 pending/cancelled 订单。
- R06：`hub_user_1` 只看到 user_id=1 的 13 个订单。
- R07：`hub_user_2` 只看到 user_id=2 的 15 个订单。
- R09：会员读取上游 API Key 基表被拒绝。
- R13：店员试图更新队列视图的 `user_id` 列被拒绝，错误 230。

说明 `dbo.Roles` 是应用层角色数据，`hub_manager/hub_staff/hub_customer/hub_guest` 才是 SQL Server 数据库角色。

### 第 9 分钟：综合验收
打开 `result/run_A/verify.sql.log`，展示末尾：

```text
PASS VFY07 product view row-by-row
PASS VFY08 member view row-by-row
PASS VFY09 balance reconciliation
PASS VFY10 usage summary reconciliation
PASS VFY11 boundary positives
PASS v0.1 verification
```

说明验收不仅检查行数，还做订单、库存、余额、汇总粒度的逐行/逐键对账。

### 第 10 分钟：双空库签名
展示：

```powershell
Compare-Object `
  (Get-Content .\result\run_A\signature.txt) `
  (Get-Content .\result\run_B\signature.txt)
```

预期无输出。说明 A/B 两个空库的 14 张业务表内容完全一致；A 库重复执行第四周脚本后的 `result/repeat_A/signature.txt` 也与首次一致。

## 4. 关键设计理由
- 金额用 `DECIMAL`，避免 FLOAT 近似误差。
- 中文业务文本用 `NVARCHAR`。
- 时间戳用 `DATETIME2(0)`。
- Inventory 关联 UpstreamAccount，因为库存表示上游账号可用 Token，不是商品件数。
- Orders 与 OrderDetails 都保存 Token 汇总属于受控冗余，`verify.sql` 检查两者一致。
- 商品销售只统计 `status='paid'`，退款、取消、待支付不计入销售额。
- 会员个人视图使用 `USER_NAME()` 绑定数据库用户，不依赖调用者可任意设置的会话变量。

## 5. 证据位置
- 首次完整复现：`result/run_A/`
- 第二次完整复现：`result/run_B/`
- 重复执行验证：`result/repeat_A/`
- 证据索引：`result/README.md`
- 阶段报告：`week4/stage_report.md`

SSMS 截图必须来自真实 GUI 操作并放到 `result/screenshots/`。没有真实截图时，不要用模拟表格或生成图片代替。

## 6. 安全注意事项
只操作本项目实验库；不要展示或读取真实密码、API Key、私钥。仓库数据中的 API Key 均为 `DEMO_NOT_A_REAL_API_KEY_*` 教学占位符。执行 UPDATE / DELETE 前确认 WHERE；一键脚本不会自动删除已有数据库。
