# 当前运行的 v1.1 数据库构建脚本

此目录从已完成的第6周提取正式运行需要的构建和验证脚本；原历史文件完整归档在 [archive/coursework/week6/v11](../../archive/coursework/week6/v11/README.md)。

Web 新库使用 python tools/app_prepare.py --suffix WebNewRun01。

独立 v1.1 构建使用 python -B db_tools/v11/run_full.py --suffix NewV11Run01。

始终使用没有用过的后缀；不要重建或覆盖旧库。业务 SQL 保留在 sql/，结果保留在 result/。
