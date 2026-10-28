# v0.1 复现与验证

2026-10-02 修复后实测使用 SQL Server Express 17.0.1135.8、ODBC sqlcmd 和 Windows 集成认证。请在仓库根目录执行。正式工具不依赖 archive。

## 从空库运行

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_v01.ps1
```

默认创建随机新库名和结果标签；手动传入 `-DatabaseName TokenHubDB_v01_<标签>` 与 `-RunLabel run_<标签>` 时，两者都必须未占用。数据库或结果目录存在时明确失败。兼容参数 `-DropExisting` 会删除同名实验库，日常复现不需要使用。

每阶段使用 `sqlcmd -b` 检查退出码，最后打印 `PASS v0.1 <实际数据库名>`。日志存于 `result/<实际标签>/`。已提交的正式验收为 `run_final_A/` 和 `run_final_B/`，对应 `TokenHubDB_v01_FinalA/B`。

## 检查内容

| 能力 | 结果/断言 |
|---|---|
| 行数 | 14 表；40 用户、100 订单、184 明细、3000 调用 |
| 经营总量 | paid 85 单、4228.90、92950000 Token |
| 约束 | C01～C14，预期错误号及必要约束名一致 |
| 权限 | R01～R17；会员隔离、越权拒绝、店员列权限 |
| 时间线 | VFY12 注册与账号有效期；VFY13 逐事件余额 |
| 有效授权 | VFY03 每表四项 CRUD；VFY14 演示用户实际基表权限 |
| 复现 | 两个新库 14 表内容签名一致 |

Q06 只统计固定快照时刻的可用低库存账号，结果为 0；库存视图的 stock_state 只看额度，因此有 2 个 low 账号。Q09 临时造边界行并回滚，回滚后验证行数与临时账号恢复。Q11 显示最近 14 天，月汇总覆盖全部周期；完整日汇总与完整月汇总才用于总量比较。修复后消耗最多的账号为 8。

```powershell
Compare-Object `
  (Get-Content .\result\run_final_A\signature.txt) `
  (Get-Content .\result\run_final_B\signature.txt)
```

预期无输出。签名证明业务行内容相同；对象定义和权限另由 SQL 验收及回归检查，不把行签名解释为所有数据库对象状态相同。

## 回归与重复执行

Python 和 SQL 集成测试命令见 [根 README](../README.md)。SQL 反例执行后回滚，必须观察到指定错误号；不把任意错误视作测试成功。阶段脚本重复执行的复核记录位于 result/recheck。

综合验收可能输出聚合消除 NULL 的提示：全会员聚合保留无 paid 订单用户，聚合函数忽略连接产生的 NULL。提示不改变验收结果；此处不将其归因于 EXCEPT 丢失集合中的 NULL 行。

## 证据截图

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\capture_evidence.ps1 `
  -Title 'verification' -SqlFile .\result\evidence_sql\21_verify_all_pass.sql `
  -Database TokenHubDB_v01_FinalA -Output .\result\screenshots\verification_new.png `
  -LogFile .\result\evidence_logs\verification_new.log
```

结果图片和日志拒绝覆盖。工具先真实执行 SQL、检查退出码和结果失败标记，再截取屏幕外实际 WinForms 输出控件；不会改动其他应用窗口。完整 UTF-16 日志另存，长输出分页，图片名追加 `_p01` 等。图片显示真实查询输出，不是 SSMS 窗口的整屏截图。双库证据可用 `-CompareDatabase` 指定第二个库。

[证据索引](../result/README.md) 列出当前全部文件；旧版证据见 [归档说明](../archive/README.md)。
