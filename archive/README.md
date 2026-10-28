# 历史材料与迁移映射

本目录保留修复前的过程材料和真实证据。它们记录当时的实现与验收，不代表当前版本正确性。正式运行只使用根 `sql/` 和 `tools/`，当前结果见 [result](../result/README.md)。

| 原位置 | 归档位置 |
|---|---|
| week1 & 2/ | coursework/week1-2/ |
| week3/ | coursework/week3/ |
| week4/ | coursework/week4/ |
| result/（旧 A/B/C、22 张旧截图等） | evidence/2026-10-01/ |
| week4/ROADMAP.md（本次审查新增） | 根 ROADMAP.md，继续更新 |
| DEMO_GUIDE.md | archive/coursework/week4/reproduction.md（旧版 v0.1 操作说明）；当前 Web 运行见 docs/webapp.md |
| 根 ai_usage_log.md / team_division.md | docs/ 下，保留历史记录并增补当前状态 |

各周原文和旧证据保留原貌，其中指向旧工作目录或当时根目录的路径按上表解释，不能直接当作当前运行命令。旧报告中“尚未提交”“截图待补”等是历史时点记录。历史源码中的教学占位符不是真实凭据。

- [第一、二周交付](coursework/week1-2/week2_deliverables_v2.md)
- [第三周交付](coursework/week3/week3_deliverables.md)
- [第四周原始交付清单](coursework/week4/week4_deliverables.md)
- [第三周人工测试 PDF](coursework/week3/人工测试演示结果.pdf)
- [修复前结果索引](evidence/2026-10-01/README.md)

`implementation-attempts/` 保存本轮首次流水线和截图布局尝试，不能计为最终证据。移动前检查源、目标均在本仓库范围；归档文件的逐项校验记录见 preservation.json。

## 第二阶段前的第 1—4 周材料归档（2026-10-28）

为使根目录直接交付第 5—9 周成果，已将原第一阶段报告、旧角色流程、旧 v0.1 操作说明、旧计划、旧课程需求及第一阶段测试截图从活动目录移至 `archive/`。此举不删除迁移链必需的 `sql/v01/`、`tools/run_v01.ps1`、验证 SQL 及基础测试。

| 原目录/文件 | 归档位置 |
|---|---|
| `report/stage_report.md`（第一阶段报告） | [coursework/week4/stage_report.md](coursework/week4/stage_report.md) |
| `report/role_workflow.md`（旧角色流程） | [coursework/week4/role_workflow.md](coursework/week4/role_workflow.md) |
| `docs/reproduction.md`（旧 v0.1 操作说明） | [coursework/week4/reproduction.md](coursework/week4/reproduction.md) |
| `docs/requirements/`（第四周要求） | [coursework/week4/requirements/](coursework/week4/requirements/) |
| `plan/week4-*.md`、`PRODUCT.md` | `coursework/week4/` |
| `result/run_final_A/B`、旧截图、旧 SQL 证据 | [evidence/stage1-legacy/](evidence/stage1-legacy/) |
| 原 550 行混合 README、旧 ROADMAP 和旧 AGENT | `coursework/week4/*_combined_before_stage2.md` |
| 整理前完整 AI 日志及旧组员分工 | `coursework/week4/*_full_history.md` |

全部移动文件逐项校验 SHA-256 或目录子文件哈希；映射及校验数据见 [stage1_to_stage2_manifest.json](stage1_to_stage2_manifest.json)。第 5—9 周仍在活动目录中的 AI 日志来自历史原记录第二阶段段落，不凭空生成旧内容。

当前入口为 [根 README](../README.md)、[第二阶段报告](../report/stage2_report.md)、[最终真实截图与 SQL 对账](../result/stage2/WebStage2A02/README.md)。可编辑 ER/架构图源码和两份 `render_*.py` **按用户要求保留**。
