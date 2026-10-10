# 第五周：ER 模型与 v0.1 设计审查

对应课程 **ch6 ER 模型**。本目录是第二阶段第五周正式交付，基于现存 14 张业务表和 17 条 FK 的 v0.1 数据库设计，**不执行结构迁移**。

## 提交入口（四类必交作业）

| 课程作业 | 文件 | 覆盖内容 |
|---|---|---|
| **ER 图：可编辑源 + 清晰导出** | [er_diagram.mmd](er_diagram.mmd)、[er_diagram.svg](er_diagram.svg)、[er_diagram.png](er_diagram.png) | 14 实体、关键属性、PK/UK/FK、17 条联系及两端文本基数。源图可在 Mermaid 编辑器修改；SVG 是重排后可放大的矢量图，不含旧符号图例 |
| **业务规则与映射清单** | [business_rules_mapping.md](business_rules_mapping.md) | 17 条 FK 逐项写出两端 min/max、关联列、实施层次，以及未被 FK 保证的业务规则 |
| **v0.1 问题清单** | [v01_issues.md](v01_issues.md) | 10 项问题/待决项、7 项保留理由、证据、影响、第六周候选方案 |
| **设计说明与验证记录** | [design_validation.md](design_validation.md) | ER 设计思路、订单多商品/会员或散客/库存查询三项演示、实测数据、8 分钟演示步骤 |

补充：[完整 14 表数据字典](data_dictionary.md)；[弱实体、多值属性、计算属性、三方联系等特殊 ER 要素审查](special_er_features.md)；[本地可再生成图像的渲染脚本](render_er.py)。

## 验证证据与复现

- [read-only SQL](../../result/week5/readonly_validation.sql)
- [真实执行日志](../../result/week5/readonly_validation.log)
- SQL Server 数据库：`TokenHubDB_v01_A`，Windows 集成认证，只执行 SELECT 和 `sys.*` 结构查询；实际得到 14 表、17 FK、3 追加 CHECK、100 订单、184 明细、68 个多明细订单、Gemini 两账号低库存。
- 当前数据库中 0 张空明细订单、0 个无库存账号，**不能推断 DDL 强制保证这两项**。
- 重新导出图：在本目录执行 `python render_er.py`（matplotlib + 中文字体）；源模型是 `er_diagram.mmd`。再次绘图只改本周 SVG/PNG，不读业务数据。
- 最新图仅展示 v0.1 **实际的物理 FK**，业务愿望/弱引用见文字映射。虚线表示非标识性外码（FK 不属于子表 PK），**不代表可空**；可选参与看两端 `0..1`、`0..*`。`OrderDetails` 是关联/存在依赖实体而非当前物理设计中的严格弱实体，计算与汇总属性在图中有文字注明。详细分类见 [特殊 ER 要素审查](special_er_features.md)。

## 尚需小组签字确认

1. 完全匿名散客是否允许下单，还是必须创建临时用户记录。
2. 同一个商品能否在同一订单出现多条独立明细。
3. 每个上游账号是否必须拥有且始终拥有一个库存行。
4. 自动补货的 `created_by` 主体如何表示；谁复核结构及业务基数。

**不要把尚未完成的同伴人工复核登记为已完成。** 所有结构调整留到第六周迁移课；本周没有 `ALTER TABLE` / `DROP` / 清库 / 自动 Git 提交。


## 本次自动验收

运行 `python qa_week5.py`：14 个 Mermaid 实体与 17 条 Mermaid 关系均和本机 SQL Server 输出的 17 个外码表对匹配；SVG XML、PNG 文件可解析；10 份当前文档的相对链接可打开。首次检查记录见 [qa.log](../../result/week5/qa.log)；本次特殊 ER 要素复核见 [qa_special_er.log](../../result/week5/qa_special_er.log)。**此 QA 不是团队人工复核**。
