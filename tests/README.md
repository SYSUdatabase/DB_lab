# 第三阶段数据库与 Web 回归测试

测试目录保留历史基础库和 Web 业务回归，并包含第10—13周程序对象、事务、权限及并发测试。历史第二阶段结果见[归档](../archive/stage2/result/README.md)。

| 测试范围 | 文件及证据 |
|---|---|
| 第10周过程、函数与 Web 接口 | `test_week10_sql.py`、`test_week10_web.py`；[40项逐例结果](../result/week10/W10FinalVerify03/results.json) |
| 第11—12周触发器、查询、分类及业务事务 | `test_week11_12_sql.py`；[SQL 结果](../result/week12/WebXY1124D/README.md) |
| 第13周并发与超时回滚 | `test_week13_sql.py`、[双会话执行器](../tools/week13_verify.py)；[正式验收](../result/week13/WebW13Run03/README.md)、[修复复验](../result/week13/WebW13Fix01/README.md)、[129项统一验收](../result/week13/WebW13Final01/README.md)、[最终134项验收](../result/week13/WebW13Restock2/README.md) |
| 基础业务、权限与回滚 | 登录注册、商品、订单、退款、员工管理、受限 SQL 身份、异常及证据工具等现有测试 |

按[根 README](../README.md#第三阶段从空库复现) 新建 WebW13 隔离批次，并保持同一终端中的实验密码与全部环境变量（包括 DB_LAB_TEST_DATABASE、DB_LAB_APP_DATABASE、DB_LAB_WEEK10_DATABASE、DB_LAB_WEEK12_DATABASE、DB_LAB_WEEK13_DATABASE、DB_LAB_TEST_SERVER、DB_LAB_PREVIEW）。执行：

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\.venv\Scripts\python.exe -m ruff check webapp tests tools
```

全量测试不应有失败、错误或跳过。第13周完整双会话现象另用 `tools/week13_verify.py` 执行；不得连接现有业务数据库。结果保存及清理按 README 对应步骤进行。
