# DB_lab - API Token 中转站数据库项目

## 项目概述
本项目是一个数据库实验课程项目，模拟一个在线API Token中转站（虚拟商品零售店），提供多种AI模型的API Token充值和转发服务。项目将从最初的业务需求分析逐步发展为支持经营分析与补货决策的应用。

## 小组成员
- 阮依成
- 陈诗翰
- 肖懿

## 项目阶段
- **第一阶段（第1-4周）**：v0.1 - 数据库初建与CRUD
- **第二阶段（第5-9周）**：v1.0 - 模式重构与应用开发
- **第三阶段（第10-13周）**：v2.0 - 数据库编程与事务处理
- **第四阶段（第14-17周）**：v3.0 - 数据调用与分析

## 当前进度
- **第一周**：已完成业务需求分析、角色识别、业务流程梳理、数据边界划定。
  - 交付物：[week1_deliverables.md](week1_deliverables.md)
- **第二周**：已完成关系模式设计，包括表结构、字段定义、码标注、样例元组。
  - 交付物：[week2_deliverables_v2.md](week2_deliverables_v2.md)（包含上游账号、库存流水、补货任务、异常记录、使用汇总表）
- **第三周**：已完成 SQL Server 建库建表、合成数据装载、CRUD 演示与空库复现验证。
  - 通用复现与演示教程：[DEMO_GUIDE.md](DEMO_GUIDE.md)
  - 实施计划：[week3_plan.md](week3_plan.md)
  - 交付说明：[week3/week3_deliverables.md](week3/week3_deliverables.md)
  - SQL 脚本：[week3/sql/](week3/sql/)
  - 数据生成器：[week3/tools/datagen.py](week3/tools/datagen.py)

## 环境要求
- SQL Server 2025 Express
- 数据库管理工具 ： SSMS

## 复现步骤
1. 克隆本仓库并确认 SQL Server、SSMS、sqlcmd 与 Python 环境可用。
2. 按照 [DEMO_GUIDE.md](DEMO_GUIDE.md) 从空数据库执行第三周脚本。
3. 复现完成后可继续按照同一教程进行课堂演示与结果核对。