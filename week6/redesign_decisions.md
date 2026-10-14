# 第六周 P2：规范化重构方案与待批准决策

依据 `dependency_normalization.md`、v0.1 DDL/约束及已备份副本的统计，以下是**建议方案，不是已经获批或执行的迁移**。在用户确认变更范围之前，不运行更改业务表的 DDL。

## 一、决策矩阵：全部核心表

| 表 | 建议 | 说明（包括无损/依赖保持与异常成本） |
|---|---|---|
| Roles | 保留 | role_id 与 role_name 都是候选码；JSON permissions 的细粒度语义尚未定义，暂不拆权限项 |
| Users | 保留 | username、email 作为额外候选码；不把电话误作唯一身份 |
| Products | 保留 | 按 provider/档位的联合候选码；历史价格不在 Products 而在订单明细 |
| UpstreamAccount | 保留 | account_id / (provider,account_name) 两候选码；与库存快照的差值关系需流程对账 |
| Inventory | 保留受控快照 | account_id 唯一；没有证明 3NF 违例。每上游账号是否必有一行尚待业务确认 |
| Employees | 保留 | 员工 account 唯一；role_id 真 FK；不与数据库角色混淆 |
| Orders | 保留受控汇总 | total_amount/total_tokens 需和明细保持事务同步；不把跨表求和误当单表 FD |
| OrderDetails | **建议暂保留**计算后存储列，记录理论非 3NF；另备可选转 PERSISTED COMPUTED 方案 | `subtotal`、`total_tokens` 可以从本行非码算出；但现有插入脚本显式填写两列，贸然改 computed 会拒绝现有合法写入。当前两个公式 CHECK 已阻止错误值，适合受控反规范化，未来同步改写路径再改 |
| InventoryLog | 保留 | reference_type/id 没有 FK；不强行推导唯一映射 |
| TokenBalances | 保留受控快照 | (user_id,model_provider) 唯一；历史余额正确性另用逐事件验证 |
| TokenUsageLogs | 保留 | 三方消费事实和 3 FK 均有业务意义；provider 匹配需独立约束或事务 |
| UsageSummary | **候选拆分：先确认业务 FD** | 若统一周期规则成立，`(period_type,period_start)→period_end` 违反 2NF；建议提取 `UsagePeriod`，详见下文。若有用户自定义周期，则此拆分无依据，维持现有表 |
| RestockTask | 保留 | created_by / assigned_to 为不同 FK；自动补货创建主体待定，不擅自改为可空 |
| ExceptionLog | 保留弱引用 | 类型化关联将影响多个目标实体；先确认引用生命周期再拆，不做不可证实的通用 FK |

## 二、拟议的唯一实质结构调整：提取周期定义（有条件）

**前提业务 FD（需明确批准）**：对全体用户，`(period_type,period_start)` 唯一确定 `period_end`，按固定统计桶定义。现有样例 daily 为同日、weekly 为起点后 6 天、monthly 为起始月份月末；这只是只读样例特征，仍须确定 weekly 的起始日规则、monthly 跨月/跨年的语义。

**原关系**：
`UsageSummary(summary_id,user_id,product_id,period_type,period_start,period_end,total_tokens_used,total_upstream_consumed,request_count,last_updated_at)`。

**候选目标**：

```text
UsagePeriod(
  period_type VARCHAR(10) NOT NULL,
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  PRIMARY KEY (period_type, period_start),
  CHECK (period_end >= period_start)
)

UsageSummary(
  summary_id INT PRIMARY KEY,
  user_id INT REFERENCES Users(user_id),
  product_id INT REFERENCES Products(product_id),
  period_type VARCHAR(10) NOT NULL,
  period_start DATE NOT NULL,
  total_tokens_used BIGINT NOT NULL,
  total_upstream_consumed BIGINT NOT NULL,
  request_count INT NOT NULL,
  last_updated_at DATETIME2(0) NOT NULL,
  UNIQUE (user_id, product_id, period_type, period_start),
  FOREIGN KEY (period_type, period_start)
    REFERENCES UsagePeriod(period_type, period_start)
)
```

**无损连接证明**：分解交集为 `(period_type,period_start)`，此交集在 `UsagePeriod` 中是主码，因此每一条汇总行经该键最多匹配一条周期定义；只要新外码验证通过，每条汇总行恰好匹配一条，使用 `JOIN` 可重建原 10 列。关系代数上 `R1∩R2 → R2` 满足经典二元无损分解条件。

**依赖保持**：`summary_id→` 汇总指标、用户/商品/周期键仍在 UsageSummary 中；`(user_id,product_id,period_type,period_start)` 仍为候选码；`(period_type,period_start)→period_end` 在 UsagePeriod 的 PK 中被显式保证。FK 保证两个关系连接，CHECK/唯一性分别各表实施。对原来的 `period_end≥period_start` CHECK 在新周期表保留。额外费用：写汇总时必须先 UPSERT 周期定义；原 `dbo.UsageSummary` 的直接查询和数据插入均需适配（兼容视图可统一输出旧列）。

**无数据丢失迁移步骤**（仅方案）：
1. 静态检查 `(period_type,period_start)` 是否存在多种 period_end，并检查所有类型是否合法；有冲突就报错、**不自动选择覆盖值**。
2. `SELECT DISTINCT period_type,period_start,period_end` 插入 UsagePeriod；先核对新表行数和唯一性。
3. 对正在读取或写入 `period_end` 的视图、样例生成器和应用脚本制定兼容修改清单，确认可安全操作后，删除旧列/旧 CHECK，给 UsageSummary 增加复合 FK。
4. 提供 `v_UsageSummaryDetailed` 兼容读取，迁移前后按同一 SQL 语义比较。
5. 历史日志、用户、订单、余额、库存及四类角色权限不能受影响；权限需适配新表/视图。
6. 完整回归通过前保留 `TokenHubDB_v01_A`、独立备份及隔离副本中的业务数据；失败从备份还原**另一名称的测试副本**，不覆盖源库。

**风险**：即使样例完全吻合，也不能代替“统一周期”业务要求。一旦允许任意自定义周期，必须先放弃上述 FD，而不能强制归为同一种 period_end。

## 三、对 OrderDetails 的存储计算列做受控保留

- 当前 `CK_OrderDetails_subtotal_formula`、`CK_OrderDetails_tokens_formula` 在数据库写入时拒绝错误公式，因此**错误值不可能作为已通过 CHECK 的行留在表中**（前提是约束启用且可信）。
- 因为 `sql/02_insert_data.sql`、`sql/03_crud_demo.sql` 等显式插入计算字段，将其改成 SQL Server GENERATED/PERSISTED 列虽能消除多值维护责任，但**不保持原 INSERT API**；按课程“迁移前后语义保持”，优先保留并记录为**有约束的、非 3NF 冗余**。
- 若未来要迁移，先改生成器、CRUD 和数据库连接层；迁移顺序为基线/约束验证→保存旧数值→调整插入语句→删公式 CHECK/旧列→新增计算列→双向业务对账→权限和合法/非法写入测试。此方案不在本次预定的首批迁移范围。

## 四、决策关口

1. **是否确认统一统计周期**（尤其是 weekly 起始日以及 monthly 的周期定义）？如果确认，批准将 `UsageSummary.period_end` 迁移到 `UsagePeriod`，调整必要查询/写入接口。
2. 如果不确认，则默认 **14 张表原样保留**，并在课程要求允许的范围内提供明确“无结构改动” `migration.sql`、异常分解实例和全面回归；不能冒充完成拆表。
3. 五周另有待定的散客、同商品多行、账号必有库存、自动补货创建人四项业务取舍，**不作为本次迁移脚本的隐式条件**。
4. 任何实迁移需要针对将运行的目标数据库副本单独审批，在本文件方案被确认前不得执行影响结构/数据的脚本。

**当前状态**：P0 基线已建立并哈希一致；P1 FD/范式分析已编写；本文件处于 **P2 方案供用户确认** 阶段。P3/P4 尚未实施，不提供伪造的 PASS。

## 五、已有实现对周期业务规则的进一步佐证

经只读审查，`tools/datagen.py` 以周一作为 weekly 起点、周日作为终点，以月首/月末作为 monthly 边界；`sql/verify.sql` VFY10 使用相同规则检查 `UsageSummary`。因此当前项目本身已经按“统一周期”生成并核对数据，业务 FD 有代码依据。副本包含 **3394 条汇总行 / 99 种周期定义**（daily 83、weekly 13、monthly 3），无周期结束日冲突。

这使 `UsagePeriod` 分解成为有根据的**优先候选**，但不等于用户已经批准影响写入接口的 DDL。仍需明确批准迁移后再实施 P3；未来若要引入自定义用户周期则需另外建模。
