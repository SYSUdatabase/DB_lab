# 第四周任务书与交付映射

[第四周任务讲解.docx](week4.docx) 复制自用户提供的下载目录原件。只将其中课程要求作为实验核对依据。未修改任务书内容。

| 原始要求 | 当前交付 |
|---|---|
| 多表连接回答业务问题 | [query.sql](../../sql/query.sql)，Q01～Q12 |
| 聚合、GROUP BY、HAVING、必要子查询 | Q02～Q05、Q07、Q10～Q12 |
| 创建并查询不同统计视图 | [view.sql](../../sql/view.sql)，四经营视图及权限用途视图 |
| 主码、外码、UNIQUE、CHECK、DEFAULT、NULL | [DDL](../../sql/01_create_tables.sql)、[constraint.sql](../../sql/constraint.sql)，合法/非法用例 |
| 按第一周角色最小授权、越权测试 | [role.sql](../../sql/role.sql)、[角色流程](../../report/role_workflow.md) |
| 从空库复现 | [README](../../README.md)、[run_v01.ps1](../../tools/run_v01.ps1) |
| 成功建库、CRUD、正常/非法/越权、查询与视图截图 | [result](../../result/README.md) |
| 设计思路、实验过程、实验总结与键设计理由 | [阶段报告](../../report/stage_report.md) |
| AI 建议、人工修改、验证结论与分工 | [AI 日志](../ai_usage_log.md)、[分工](../team_division.md) |
| 之前每周任务中的要求也要包含 | [历史周次材料](../../archive/README.md)，根 README 与阶段报告整合核心结论 |

任务书没有指定必须三库复现、特定查询/用例数量或 DOCX/PDF 报告格式。两库签名和反例回归是本项目增强验收。第二名成员独立复现属于团队自定复核，不伪称教师硬性条款或已完成。

第一周角色允许会员下单/支付/改资料及店员退款，当前阶段仅提供相应只读或受限队列能力；差异在角色流程和阶段报告中说明，后续以校验身份与事务一致性的存储过程实现，不直接开放任意基表写权限。


## 第五周任务书要求与交付映射（ch6 ER）

依据用户提供的《第五周任务讲解.docx》（未复制/改写任务书原件）。第五周先对既有 v0.1 分析，不直接实施第六周的数据库结构调整。

| 第五周作业 | 当前交付 |
|---|---|
| ER 图可编辑源文件 + 清晰导出图 | [源图 mmd](../../week5/er_diagram.mmd)、[SVG](../../week5/er_diagram.svg)、[PNG](../../week5/er_diagram.png) |
| 核心实体、属性、主码、候选码、外码；命名与字典一致 | [14 表数据字典](../../week5/data_dictionary.md) |
| 基数与参与约束，业务规则/联系映射及对应实现 | [17 FK 与规则清单](../../week5/business_rules_mapping.md) |
| v0.1 问题、业务证据、影响、改进方向和保留理由 | [问题与保留清单](../../week5/v01_issues.md) |
| 设计说明及多商品订单、会员/散客购买、库存查询验证 | [设计与演示记录](../../week5/design_validation.md)、[只读 SQL 和真实输出](../../result/week5/README.md) |

图表、静态检查和本周只读查询已完成；小组业务分歧及第二名组员独立复核仍待确认，不能标作完成。第六周才制作迁移脚本。

## 第六周 ch7 函数依赖与规范化（2026-10-14）

| 本周要求 | 实际交付 |
|---|---|
| FD、全部候选码、1NF/2NF/3NF、三类更新异常 | [14 表逐项分析](../../week6/dependency_normalization.md) |
| 目标设计、保留和拆分理由、无损连接和依赖保持 | [重构决策](../../week6/redesign_decisions.md)、[v1.0 数据字典](../../week6/data_dictionary_v10.md) |
| `migration.sql` + 实际副本迁移日志 | [迁移脚本](../../sql/migration.sql)、[迁移结果](../../result/week6/README.md) |
| `regression.sql` + 原业务统计/合法性/权限回归 | [回归脚本](../../sql/regression.sql)、[执行日志索引](../../result/week6/README.md) |
| README、报告、ER 和 AI 使用文档 | [第六周交付入口](../../week6/README.md)、[报告素材](../../week6/report_material.md)、[可编辑 v1.0 ER](../../week6/er_diagram_v10.mmd)、[AI 使用记录](../ai使用文档.md) |

**结果边界**：周期拆分和结构/角色回归已完成，但选用的 v0.1_A 源库原本存在 VFY12/VFY13 历史异常，因此不能把旧数据时间线完整性登记为全部通过。

## 第五周设计问题的后续修复

已在独立的 v1.1 副本对部分可确定的约束实施前向修复，并执行新增正反例与 v1.0 核心回归，详见 [I01–I10 最新状态](../../week6/issue_fixes/README.md)。未决散客、同单重复商品、库存必需性、系统补货身份及原历史数据缺陷未被擅自改成已解决。

## 用户确认的第五周业务取舍（2026-10-14）

I02 同商品合并数量、I03 必须先建 Users、I04 账号必配 Inventory、I07 manual/system 创建人规则已在独立 v1.1 副本实施并通过正反例。具体结构、可编辑 ER、兼容性及执行日志见 [v1.1 数据字典和验收](../../week6/issue_fixes/data_dictionary_v11.md)。第六周的原始规范化 v1.0 验证结果未被覆盖。
