# 第五周：ER 模型与 v0.1 设计审查

本目录整理 v0.1 数据库的第五周 ER 模型、业务规则与设计审查材料，覆盖 14 张业务表和 17 条外键。**不修改数据库结构**。

## 文档入口

| 内容 | 文件 | 说明 |
|---|---|---|
| **ER 图：可编辑源 + 清晰导出** | [er_diagram.mmd](er_diagram.mmd)、[er_diagram.svg](er_diagram.svg)、[er_diagram.png](er_diagram.png) | 14 实体、关键属性、PK/UK/FK、17 条联系及两端文本基数。源图可在 Mermaid 编辑器修改；SVG 是重排后可放大的矢量图，附有文字图例 |
| **业务规则与映射清单** | [business_rules_mapping.md](business_rules_mapping.md) | 17 条 FK 逐项写出两端 min/max、关联列、实施层次，以及未被 FK 保证的业务规则 |
| **v0.1 问题清单** | [v01_issues.md](v01_issues.md) | 10 项问题/待决项、7 项保留理由、证据、影响、第六周候选方案 |
| **设计说明与验证记录** | [design_validation.md](design_validation.md) | ER 设计思路、订单多商品/会员或散客/库存三项业务场景、SQL 查询及核对结果 |

补充：[完整 14 表数据字典](data_dictionary.md)；[独立技术复核记录](independent_review.md)；[弱实体、多值属性、计算属性、三方联系等特殊 ER 要素审查](special_er_features.md)；[本地可再生成图像的渲染脚本](render_er.py)。

## 验证证据与复现

- [read-only SQL](../result/week5/readonly_validation.sql)
- [查询结果日志](../result/week5/readonly_validation.log)
- SQL Server 数据库：`TokenHubDB_v01_A`，Windows 集成认证，只执行 SELECT 和 `sys.*` 结构查询；查询得到 14 表、17 FK、3 追加 CHECK、100 订单、184 明细、68 个多明细订单、Gemini 两账号低库存。
- 当前数据库中 0 张空明细订单、0 个无库存账号，**不能推断 DDL 强制保证这两项**。
- 重新导出图：在本目录执行 `python render_er.py`（matplotlib + 中文字体）；源模型是 `er_diagram.mmd`。再次绘图只改本周 SVG/PNG，不读业务数据。
- 最新 SVG/PNG 的 **17 条关系均为实线**，线型只表示现有实体联系；是否可选参与须看两端 `0..1`、`1..1`、`0..*` 等基数。编辑源 `.mmd` 按 Mermaid 规范保留 `..` 来标识非标识性 FK（这些 FK 不属于子表 PK），直接由 Mermaid 渲染时可能显示虚线；PNG/SVG 由 `render_er.py` 统一输出实线。业务愿望/弱引用另见文字映射；`OrderDetails` 是关联实体而非当前物理主码意义下的严格弱实体。详见 [特殊 ER 要素审查](special_er_features.md)。
- **Employees → RestockTask 两条线不是重复**：`created_by → Employees.employee_id` 为必须指定的创建人（任务端 `1..1`）；`assigned_to → Employees.employee_id` 为可不指派的处理人（任务端 `0..1`）。员工对两种角色分别都可对应 `0..*` 个任务；两条 FK 分别是 `FK_RestockTask_CreatedBy` 和 `FK_RestockTask_AssignedTo`，图面用紫色和两段角色标记区分。

## 人工复核及后续业务决定

第五周 ER 模型、数据字典、17 条外键映射、基数和 v0.1 问题清单的**人工复核已完成**。复核依据见 [技术复核记录](independent_review.md)，分工见 [team_division.md](../docs/team_division.md)。

以下为后续业务规则取舍，不是第五周 ER/DDL 复核未完成：

1. 散客是否允许无账户下单，或必须创建临时用户记录。
2. 同一个商品能否在同一订单出现多条独立明细。
3. 每个上游账号是否必须始终拥有一个库存行。
4. 自动补货任务的 `created_by` 是否需要系统主体及其建模方式。

v0.1 的现有约束和上述分歧已记入 [问题清单](v01_issues.md)；结构调整留待后续阶段。


## 本次自动验收

`python qa_week5.py` 通过：14 个实体、17 条 FK 与 SQL 文件一致；SVG/PNG 可解析，文档相对链接有效。历史检查记录：[qa.log](../result/week5/qa.log)、[qa_special_er.log](../result/week5/qa_special_er.log)。
