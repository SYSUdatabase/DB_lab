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
