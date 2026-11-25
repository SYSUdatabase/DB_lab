# 第二阶段材料归档（第5—9周）

这些材料从项目活动目录迁入 `archive/stage2/`，供历史查阅，不再作为第三阶段交付的主要说明。归档时已调整文件内的相对链接；正式程序和 SQL 仍使用项目根目录的 `webapp/`、`sql/`、`tools/` 和 `tests/`，不依赖归档文件运行。

| 原位置 | 当前归档位置 | 内容 |
|---|---|---|
| `docs/stage2_acceptance.md` | [docs/stage2_acceptance.md](docs/stage2_acceptance.md) | 第二阶段各角色人工验收清单 |
| `docs/stage2_dashboard.md` | [docs/stage2_dashboard.md](docs/stage2_dashboard.md) | 第二阶段运营大屏及部署说明 |
| `report/stage2_report.md` | [report/stage2_report.md](report/stage2_report.md) | 第二阶段报告、截图与 SQL 核对引用 |

过期的 `docs/stage2_ppt_walkthrough.md` 已按要求直接删除，不归档。两份活动 AI 使用文档中仅与该展示流程相关的旧条目已移除；与实际 SQL、Web、事务、验收等有关的记录继续保留。当前第三阶段第10—12周的代码和报告仍在根目录正常维护。

## SQL Server 历史实验库清理（2026-11-23）

在本机 `localhost\\SQLEXPRESS` 对 45 个项目数据库逐个只读盘点，并确认拟清理库没有活动 SQL 用户会话。删除 40 个旧测试/复现数据库，保留 5 个明确需要的基线或历史业务验收库；删除后查询 `sys.databases`，与保留白名单完全一致。完整按名记录见[清理清单](database_cleanup_20261123.json)。

保留库分别为 `TokenHubDB_v01_A`（规范化回归引用的原始基线）、`TokenHubDB_v11_WebManualA01`（现有手册和管理脚本引用）、`TokenHubDB_v11_WebFinal1106A`（第二阶段完整测试批次）、`TokenHubDB_v11_WebEmp26A01`（员工管理验收批次）和 `TokenHubDB_v11_WebStage2A02`（浏览器和数据库对账批次）。此操作不清除 Git 下已有的历史验收日志或 SQL 备份文件；如需重新验收第10—12周，应使用 `tools/app_prepare.py` 的新后缀独立建库。

## 第三阶段接续归档（2026-11-23）

为了使活动目录只呈现第10周及以后的交付，以下第5—9周材料归档至本目录：

- [第5周ER模型计划](plan/week5-er-model-plan.md)、[第6周规范化迁移计划](plan/week6-normalization-migration-plan.md)、[第7—9周Web计划](plan/week7-9-webapp-plan.md)
- [第二阶段完整组员分工](docs/team_division_stage2.md)
- [第二阶段AI详细日志](docs/ai_usage_log_stage2.md)、[第二阶段AI使用文档](docs/ai使用文档_stage2.md)
- [第二阶段及Web交付旧路线记录](ROADMAP_stage2.md)

当前README、AI日志、团队分工和活动计划从第10周开始；第13周并发控制已实现。

## 历史结果归档与重复构建日志精简（2026-11-25）

第5—9周的结果和历史构建日志整理见[历史结果索引](result/README.md)。第三阶段受限账户补验收 WebXY1123R 保留在活动结果目录；旧备份和压缩归档校验见[清理清单](result/cleanup_manifest_20261125.json)。
