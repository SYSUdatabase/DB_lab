# 全量自动测试记录（WebXY1123K，审计表增加登录名后）

第11周审计表增加 `login_name` 后，[WebXY1123J](../../week11/WebXY1123J/README.md) 只运行了第11周触发器测试与 `tests/test_week11_12_sql.py`。为确认改动未影响其他功能，2026-11-23 另用新后缀 WebXY1123K 从空 v0.1 构建至第12周，运行全部 Python 测试。

| 步骤 | 命令与结果 |
|---|---|
| 建库 | `tools/app_prepare.py --suffix WebXY1123K --with-week10 --with-week11 --with-week12`，退出码 0，第10、11、12周安装日志均为 PASS（`result/webapp/WebXY1123K/`） |
| 全量测试 | `DB_LAB_TEST_DATABASE` 指向 `TokenHubDB_v01_WebXY1123K`，`DB_LAB_APP_DATABASE`、`DB_LAB_WEEK10_DATABASE`、`DB_LAB_WEEK12_DATABASE` 指向 `TokenHubDB_v11_WebXY1123K`，`DB_LAB_PREVIEW=1`；`python -m unittest discover -s tests -v` 共 124 项，OK，0 失败、0 跳过，用时 77.8 秒（[原始日志](full_unittest.log)） |
| 清理 | `tools/cleanup_reproduction.ps1 -Suffix WebXY1123K -KeepEvidence` 删除三个数据库与两份备份，脚本核验 PASS；本目录与构建日志保留 |

实验密码与会话密钥只在本次运行的进程环境中生成和使用，未写入任何文件。
