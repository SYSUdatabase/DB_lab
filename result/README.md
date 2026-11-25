# 第三阶段实验结果索引（第10—13周）

本目录重点保留第三阶段各周 SQL 调用、异常、事务回滚及并发验证证据。原第5—9周结果已经归档。

| 周次 | 主要结果与证据 |
|---|---|
| 10 | [40项逐例结果](week10/W10FinalVerify03/results.json)、[全量115项与专项结果](week10/README.md) |
| 11 | [14项触发器验证](week13/WebW13Run03/test_trigger.log)、[窗口查询](week13/WebW13Run03/window_query.log) |
| 12 | [分类维护6项](week13/WebW13Run03/test_category_maintenance.log)、[递归查询](week13/WebW13Run03/recursive_query.log)、[事务14项](week13/WebW13Run03/test_transactions.log)、[受限账户验收](week12/WebXY1123R/README.md) |
| 13 | [正式批次](week13/WebW13Run03/README.md)、[修复专项复验](week13/WebW13Fix01/README.md)、[129项统一验收](week13/WebW13Final01/README.md)、[最终134项验收](week13/WebW13Restock2/README.md) |

第三阶段报告见 [stage3_report.md](../report/stage3_report.md)，复现说明见 [根 README](../README.md)。

## 目录整理

- 第5周、第6周的独立历史验证及第2阶段结果已转入 [历史结果归档](../archive/stage2/result/README.md)。
- `week6/v11/` 保留当前建库工具的输出路径、第三阶段及现存历史业务库有关的构建记录；旧的独立复现批次已归档。
- `source_Web*` 是基础库创建与校验日志，而不是数据库文件。重复历史构建日志已无损压缩，保留有直接引用及有代表性的原始目录。归档可按批次解压，清单含每个文件的 SHA-256。
- `webapp/` 保留安装清单及各阶段建库过程，`cleanup/` 保留清理记录。
