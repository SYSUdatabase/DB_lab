-- 第12周事务验证：订单完成事务、补货入库事务的正常提交、中途失败回滚、重复调用与规则拒绝。
-- 在安装了第12周扩展的专用实验库上执行。每个用例先新建自己的订单或补货单并记录初始值，
-- 相当于每次从重置后的数据开始；检查涉及的全部业务表，而不只看是否报错。
-- 最后一个结果集按“编号|类别|初始数据|操作|预期结果|实际结果|是否符合”输出。
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @r TABLE(case_no VARCHAR(8),category NVARCHAR(20),initial NVARCHAR(600),operation NVARCHAR(400),
 expected NVARCHAR(400),actual NVARCHAR(600),passed BIT);
DECLARE @tag VARCHAR(12)=FORMAT(SYSDATETIME(),'MMddHHmmss');
DECLARE @uid INT,@admin INT,@p INT,@q INT,@big INT,@acct INT,@o INT,@err NVARCHAR(400),
 @bal0 BIGINT,@bal1 BIGINT,@lots0 INT,@lots1 INT,@st VARCHAR(24),@amt DECIMAL(10,2),@tok BIGINT,
 @task INT,@inv0 BIGINT,@inv1 BIGINT,@quota0 BIGINT,@quota1 BIGINT,@log0 INT,@log1 INT,@aud0 INT,@aud1 INT,
 @tst VARCHAR(20),@actual BIGINT,@done DATETIME2(0),@o2 INT;
SELECT @uid=user_id FROM dbo.Users WHERE username='web_customer';
SELECT @admin=e.employee_id FROM dbo.Employees e JOIN dbo.Roles r ON r.role_id=e.role_id
 WHERE e.account='web_admin' AND r.role_name='admin';
-- 测试数据：Other 供应商的商品 P、Q（不同档位）与一份超过可售余量的大套餐，以及一个待补货的上游账号。
INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status)
VALUES(N'W12商品P_'+@tag,N'第12周测试商品P',12.00,'Other',110000+CONVERT(INT,RIGHT(@tag,5)),110000+CONVERT(INT,RIGHT(@tag,5)),'active');
SET @p=SCOPE_IDENTITY();
INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status)
VALUES(N'W12商品Q_'+@tag,N'第12周测试商品Q',8.00,'Other',210000+CONVERT(INT,RIGHT(@tag,5)),210000+CONVERT(INT,RIGHT(@tag,5)),'active');
SET @q=SCOPE_IDENTITY();
INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status)
VALUES(N'W12超量套餐_'+@tag,N'第12周库存不足测试',1.00,'Other',1990000000-CONVERT(INT,RIGHT(@tag,5)),1990000000-CONVERT(INT,RIGHT(@tag,5)),'active');
SET @big=SCOPE_IDENTITY();
INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,used_quota,safety_threshold,status,expires_at)
VALUES('Other',N'W12补货账号_'+@tag,N'sk-w12-'+@tag,100000,0,1000,'active','20271231');
SET @acct=SCOPE_IDENTITY();

-- ===== 订单完成事务 =====
-- T1 正常提交：P×2、Q×1、再加 P×1（同商品合并为 P×3），完成后余额按供应商汇总增加、每条明细发放批次。
EXEC dbo.usp_W5_CreateRegisteredOrder @uid,@emit_result=0,@app_result_id=@o OUTPUT;
EXEC dbo.usp_W5_AddMergedOrderItem @o,@p,2,@emit_result=0;
EXEC dbo.usp_W5_AddMergedOrderItem @o,@q,1,@emit_result=0;
EXEC dbo.usp_W5_AddMergedOrderItem @o,@p,1,@emit_result=0;
SELECT @bal0=COALESCE((SELECT remaining_tokens FROM dbo.TokenBalances WHERE user_id=@uid AND model_provider='Other'),0);
SELECT @amt=total_amount,@tok=total_tokens FROM dbo.Orders WHERE order_id=@o;
BEGIN TRY EXEC w12.usp_CompleteOrder @o,@emit_result=0; SET @err=NULL; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER(),N' ',ERROR_MESSAGE()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
SELECT @bal1=remaining_tokens FROM dbo.TokenBalances WHERE user_id=@uid AND model_provider='Other';
SELECT @lots1=COUNT(*) FROM dbo.OrderTokenLots l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id WHERE d.order_id=@o;
SELECT @st=status FROM dbo.Orders WHERE order_id=@o;
INSERT @r VALUES('T1',N'订单·正常提交',
 N'订单 #'+CONVERT(NVARCHAR(11),@o)+N' pending，明细 2 条（P×3、Q×1），金额 '+CONVERT(NVARCHAR(20),@amt)+N'，Token '+CONVERT(NVARCHAR(20),@tok)
 +N'；顾客 Other 余额 '+CONVERT(NVARCHAR(20),@bal0)+N'；批次 0',
 N'EXEC w12.usp_CompleteOrder '+CONVERT(NVARCHAR(11),@o),
 N'状态 paid；余额 +'+CONVERT(NVARCHAR(20),@tok)+N'；批次 2 条',
 COALESCE(@err,N'状态 '+@st+N'；余额 '+CONVERT(NVARCHAR(20),@bal0)+N'→'+CONVERT(NVARCHAR(20),@bal1)+N'；批次 '+CONVERT(NVARCHAR(11),@lots1)+N' 条'),
 CASE WHEN @err IS NULL AND @st='paid' AND @bal1-@bal0=@tok AND @lots1=2 THEN 1 ELSE 0 END);

-- T2 重复调用：对 T1 的订单再次执行完成事务，不能第二次记入余额或发放批次。
SET @bal0=@bal1; SET @lots0=@lots1;
BEGIN TRY EXEC w12.usp_CompleteOrder @o,@emit_result=0; SET @err=N'未报错'; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
SELECT @bal1=remaining_tokens FROM dbo.TokenBalances WHERE user_id=@uid AND model_provider='Other';
SELECT @lots1=COUNT(*) FROM dbo.OrderTokenLots l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id WHERE d.order_id=@o;
INSERT @r VALUES('T2',N'订单·重复调用',N'订单 #'+CONVERT(NVARCHAR(11),@o)+N' 已 paid；余额 '+CONVERT(NVARCHAR(20),@bal0)+N'；批次 '+CONVERT(NVARCHAR(11),@lots0),
 N'再次 EXEC w12.usp_CompleteOrder '+CONVERT(NVARCHAR(11),@o),N'返回 53131（已完成）；余额、批次不变',
 @err+N'；余额 '+CONVERT(NVARCHAR(20),@bal1)+N'；批次 '+CONVERT(NVARCHAR(11),@lots1),
 CASE WHEN @err=N'错误 53131' AND @bal1=@bal0 AND @lots1=@lots0 THEN 1 ELSE 0 END);

-- T3 中途失败回滚：余额已经记入之后、订单改为 paid 之前主动抛错。
EXEC dbo.usp_W5_CreateRegisteredOrder @uid,@emit_result=0,@app_result_id=@o2 OUTPUT;
EXEC dbo.usp_W5_AddMergedOrderItem @o2,@q,2,@emit_result=0;
SELECT @bal0=remaining_tokens FROM dbo.TokenBalances WHERE user_id=@uid AND model_provider='Other';
EXEC sys.sp_set_session_context @key=N'w12.fail_point',@value=N'order_after_credit';
BEGIN TRY EXEC w12.usp_CompleteOrder @o2,@emit_result=0; SET @err=N'未报错'; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
EXEC sys.sp_set_session_context @key=N'w12.fail_point',@value=NULL;
SELECT @bal1=remaining_tokens FROM dbo.TokenBalances WHERE user_id=@uid AND model_provider='Other';
SELECT @lots1=COUNT(*) FROM dbo.OrderTokenLots l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id WHERE d.order_id=@o2;
SELECT @st=status FROM dbo.Orders WHERE order_id=@o2;
INSERT @r VALUES('T3',N'订单·中途失败回滚',N'订单 #'+CONVERT(NVARCHAR(11),@o2)+N' pending（Q×2，Token '+CONVERT(NVARCHAR(20),(SELECT total_tokens FROM dbo.Orders WHERE order_id=@o2))
 +N'）；余额 '+CONVERT(NVARCHAR(20),@bal0)+N'；批次 0',
 N'设故障点 order_after_credit 后完成订单（余额已加、状态未改时抛错）',N'报错 54490；状态仍 pending；余额恢复为初始值；批次 0',
 @err+N'；状态 '+@st+N'；余额 '+CONVERT(NVARCHAR(20),@bal1)+N'；批次 '+CONVERT(NVARCHAR(11),@lots1),
 CASE WHEN @err=N'错误 54490' AND @st='pending' AND @bal1=@bal0 AND @lots1=0 THEN 1 ELSE 0 END);

-- T4 回滚后重新执行：去掉故障点，同一订单能正常完成，说明失败没有留下半成品。
BEGIN TRY EXEC w12.usp_CompleteOrder @o2,@emit_result=0; SET @err=NULL; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
SELECT @bal1=remaining_tokens FROM dbo.TokenBalances WHERE user_id=@uid AND model_provider='Other';
SELECT @st=status FROM dbo.Orders WHERE order_id=@o2;
INSERT @r VALUES('T4',N'订单·正常提交',N'T3 回滚后的订单 #'+CONVERT(NVARCHAR(11),@o2)+N' pending；余额 '+CONVERT(NVARCHAR(20),@bal0),
 N'不设故障点，再次完成',N'状态 paid；余额增加 Q×2 的 Token',
 COALESCE(@err,N'状态 '+@st+N'；余额 '+CONVERT(NVARCHAR(20),@bal0)+N'→'+CONVERT(NVARCHAR(20),@bal1)),
 CASE WHEN @err IS NULL AND @st='paid' AND @bal1-@bal0=(SELECT total_tokens FROM dbo.Orders WHERE order_id=@o2) THEN 1 ELSE 0 END);

-- T5 规则拒绝：不存在的订单、无明细的订单、库存不足的订单，三者都不改变任何数据。
DECLARE @o3 INT,@o4 INT;
EXEC dbo.usp_W5_CreateRegisteredOrder @uid,@emit_result=0,@app_result_id=@o3 OUTPUT;
EXEC dbo.usp_W5_CreateRegisteredOrder @uid,@emit_result=0,@app_result_id=@o4 OUTPUT;
EXEC dbo.usp_W5_AddMergedOrderItem @o4,@big,1,@emit_result=0;
SELECT @bal0=remaining_tokens FROM dbo.TokenBalances WHERE user_id=@uid AND model_provider='Other';
DECLARE @e1 NVARCHAR(40),@e2 NVARCHAR(40),@e3 NVARCHAR(40);
BEGIN TRY EXEC w12.usp_CompleteOrder -1,@emit_result=0; SET @e1=N'未报错'; END TRY
BEGIN CATCH SET @e1=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
BEGIN TRY EXEC w12.usp_CompleteOrder @o3,@emit_result=0; SET @e2=N'未报错'; END TRY
BEGIN CATCH SET @e2=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
BEGIN TRY EXEC w12.usp_CompleteOrder @o4,@emit_result=0; SET @e3=N'未报错'; END TRY
BEGIN CATCH SET @e3=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
SELECT @bal1=remaining_tokens FROM dbo.TokenBalances WHERE user_id=@uid AND model_provider='Other';
INSERT @r VALUES('T5',N'订单·规则拒绝',N'订单 -1 不存在；#'+CONVERT(NVARCHAR(11),@o3)+N' 无明细；#'+CONVERT(NVARCHAR(11),@o4)+N' 需求 '
 +CONVERT(NVARCHAR(20),(SELECT total_tokens FROM dbo.Orders WHERE order_id=@o4))+N' 超过 Other 可售余量 '
 +CONVERT(NVARCHAR(40),(SELECT available_quota-outstanding_tokens FROM w11.fn_ProviderSellable('Other')))+N'；余额 '+CONVERT(NVARCHAR(20),@bal0),
 N'依次完成这三张订单',N'分别返回 53123、53125、53132；两张订单仍 pending；余额不变',
 @e1+N'；'+@e2+N'；'+@e3+N'；状态 '+(SELECT status FROM dbo.Orders WHERE order_id=@o3)+N' / '+(SELECT status FROM dbo.Orders WHERE order_id=@o4)
 +N'；余额 '+CONVERT(NVARCHAR(20),@bal1),
 CASE WHEN @e1=N'错误 53123' AND @e2=N'错误 53125' AND @e3=N'错误 53132' AND @bal1=@bal0
  AND 'pending'=(SELECT status FROM dbo.Orders WHERE order_id=@o3) AND 'pending'=(SELECT status FROM dbo.Orders WHERE order_id=@o4) THEN 1 ELSE 0 END);

-- T6 原入口已替换：Web 调用的 dbo.usp_W6_PayPendingOrder 现在委托给 w12.usp_CompleteOrder。
DECLARE @o5 INT;
EXEC dbo.usp_W5_CreateRegisteredOrder @uid,@emit_result=0,@app_result_id=@o5 OUTPUT;
EXEC dbo.usp_W5_AddMergedOrderItem @o5,@p,1,@emit_result=0;
BEGIN TRY EXEC dbo.usp_W6_PayPendingOrder @o5,@emit_result=0; EXEC dbo.usp_W6_PayPendingOrder @o5,@emit_result=0; SET @err=N'第二次未报错'; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
INSERT @r VALUES('T6',N'订单·原入口',N'订单 #'+CONVERT(NVARCHAR(11),@o5)+N' pending（P×1）',
 N'连续两次 EXEC dbo.usp_W6_PayPendingOrder（Web“模拟支付”调用的过程）',N'第一次 paid，第二次返回 53131；批次 1 条',
 N'第二次 '+@err+N'；状态 '+(SELECT status FROM dbo.Orders WHERE order_id=@o5)+N'；批次 '
 +CONVERT(NVARCHAR(11),(SELECT COUNT(*) FROM dbo.OrderTokenLots l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id WHERE d.order_id=@o5))+N' 条',
 CASE WHEN @err=N'错误 53131' AND 'paid'=(SELECT status FROM dbo.Orders WHERE order_id=@o5)
  AND 1=(SELECT COUNT(*) FROM dbo.OrderTokenLots l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id WHERE d.order_id=@o5) THEN 1 ELSE 0 END);

-- ===== 补货入库事务 =====
-- R1 正常提交：管理员填写补货单（计划 10000），实际到货 8000。
INSERT dbo.RestockTask(account_id,trigger_reason,restock_method,target_amount,created_by,assigned_to,status)
VALUES(@acct,'manual','manual_purchase',10000,@admin,@admin,'pending');
SET @task=SCOPE_IDENTITY();
SELECT @inv0=i.current_quota,@quota0=a.total_quota FROM dbo.Inventory i JOIN dbo.UpstreamAccount a ON a.account_id=i.account_id WHERE i.account_id=@acct;
SELECT @log0=COUNT(*) FROM dbo.InventoryLog WHERE account_id=@acct;
SELECT @aud0=COUNT(*) FROM w11.InventoryAudit WHERE account_id=@acct;
BEGIN TRY EXEC w12.usp_ReceiveRestock @task,8000,@emit_result=0; SET @err=NULL; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER(),N' ',ERROR_MESSAGE()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
SELECT @inv1=i.current_quota,@quota1=a.total_quota FROM dbo.Inventory i JOIN dbo.UpstreamAccount a ON a.account_id=i.account_id WHERE i.account_id=@acct;
SELECT @log1=COUNT(*) FROM dbo.InventoryLog WHERE account_id=@acct;
SELECT @aud1=COUNT(*) FROM w11.InventoryAudit WHERE account_id=@acct;
SELECT @tst=status,@actual=actual_amount,@done=completed_at FROM dbo.RestockTask WHERE task_id=@task;
INSERT @r VALUES('R1',N'补货·正常提交',N'补货单 #'+CONVERT(NVARCHAR(11),@task)+N' pending，账号 #'+CONVERT(NVARCHAR(11),@acct)+N' 计划 10000；库存 '
 +CONVERT(NVARCHAR(20),@inv0)+N'，总额度 '+CONVERT(NVARCHAR(20),@quota0)+N'；流水 '+CONVERT(NVARCHAR(11),@log0)+N'，审计 '+CONVERT(NVARCHAR(11),@aud0),
 N'EXEC w12.usp_ReceiveRestock '+CONVERT(NVARCHAR(11),@task)+N',8000',
 N'库存、总额度各 +8000；流水 +1；审计 +1；单据 completed，实际 8000，有入库时间',
 COALESCE(@err,N'库存 '+CONVERT(NVARCHAR(20),@inv1)+N'，总额度 '+CONVERT(NVARCHAR(20),@quota1)+N'；流水 '+CONVERT(NVARCHAR(11),@log1)+N'，审计 '+CONVERT(NVARCHAR(11),@aud1)
 +N'；单据 '+@tst+N'，实际 '+COALESCE(CONVERT(NVARCHAR(20),@actual),N'NULL')+N'，入库时间'+CASE WHEN @done IS NULL THEN N'为空' ELSE N'已填' END),
 CASE WHEN @err IS NULL AND @inv1-@inv0=8000 AND @quota1-@quota0=8000 AND @log1-@log0=1 AND @aud1-@aud0=1
  AND @tst='completed' AND @actual=8000 AND @done IS NOT NULL THEN 1 ELSE 0 END);

-- R2 重复调用：同一补货单再次入库，库存不能再增加。
SET @inv0=@inv1; SET @quota0=@quota1; SET @log0=@log1; SET @aud0=@aud1;
BEGIN TRY EXEC w12.usp_ReceiveRestock @task,8000,@emit_result=0; SET @err=N'未报错'; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
SELECT @inv1=i.current_quota,@quota1=a.total_quota FROM dbo.Inventory i JOIN dbo.UpstreamAccount a ON a.account_id=i.account_id WHERE i.account_id=@acct;
SELECT @log1=COUNT(*) FROM dbo.InventoryLog WHERE account_id=@acct;
INSERT @r VALUES('R2',N'补货·重复调用',N'补货单 #'+CONVERT(NVARCHAR(11),@task)+N' 已 completed；库存 '+CONVERT(NVARCHAR(20),@inv0)+N'；流水 '+CONVERT(NVARCHAR(11),@log0),
 N'再次 EXEC w12.usp_ReceiveRestock '+CONVERT(NVARCHAR(11),@task)+N',8000',N'返回 53311（已入库）；库存、总额度、流水不变',
 @err+N'；库存 '+CONVERT(NVARCHAR(20),@inv1)+N'，总额度 '+CONVERT(NVARCHAR(20),@quota1)+N'；流水 '+CONVERT(NVARCHAR(11),@log1),
 CASE WHEN @err=N'错误 53311' AND @inv1=@inv0 AND @quota1=@quota0 AND @log1=@log0 THEN 1 ELSE 0 END);

-- R3 中途失败回滚：库存与总额度已增加、流水已写入之后，单据改为 completed 之前主动抛错。
DECLARE @task2 INT;
INSERT dbo.RestockTask(account_id,trigger_reason,restock_method,target_amount,created_by,assigned_to,status)
VALUES(@acct,'manual','manual_purchase',5000,@admin,@admin,'pending');
SET @task2=SCOPE_IDENTITY();
SELECT @inv0=i.current_quota,@quota0=a.total_quota FROM dbo.Inventory i JOIN dbo.UpstreamAccount a ON a.account_id=i.account_id WHERE i.account_id=@acct;
SELECT @log0=COUNT(*) FROM dbo.InventoryLog WHERE account_id=@acct;
SELECT @aud0=COUNT(*) FROM w11.InventoryAudit WHERE account_id=@acct;
EXEC sys.sp_set_session_context @key=N'w12.fail_point',@value=N'restock_after_inventory';
BEGIN TRY EXEC w12.usp_ReceiveRestock @task2,5000,@emit_result=0; SET @err=N'未报错'; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
EXEC sys.sp_set_session_context @key=N'w12.fail_point',@value=NULL;
SELECT @inv1=i.current_quota,@quota1=a.total_quota FROM dbo.Inventory i JOIN dbo.UpstreamAccount a ON a.account_id=i.account_id WHERE i.account_id=@acct;
SELECT @log1=COUNT(*) FROM dbo.InventoryLog WHERE account_id=@acct;
SELECT @aud1=COUNT(*) FROM w11.InventoryAudit WHERE account_id=@acct;
SELECT @tst=status,@actual=actual_amount,@done=completed_at FROM dbo.RestockTask WHERE task_id=@task2;
INSERT @r VALUES('R3',N'补货·中途失败回滚',N'补货单 #'+CONVERT(NVARCHAR(11),@task2)+N' pending 计划 5000；库存 '+CONVERT(NVARCHAR(20),@inv0)
 +N'，总额度 '+CONVERT(NVARCHAR(20),@quota0)+N'；流水 '+CONVERT(NVARCHAR(11),@log0)+N'，审计 '+CONVERT(NVARCHAR(11),@aud0),
 N'设故障点 restock_after_inventory 后入库 5000（库存已加、单据未完成时抛错）',
 N'报错 54491；库存、总额度、流水、审计都恢复为初始值；单据仍 pending，实际量与入库时间为空',
 @err+N'；库存 '+CONVERT(NVARCHAR(20),@inv1)+N'，总额度 '+CONVERT(NVARCHAR(20),@quota1)+N'；流水 '+CONVERT(NVARCHAR(11),@log1)+N'，审计 '+CONVERT(NVARCHAR(11),@aud1)
 +N'；单据 '+@tst+N'，实际 '+COALESCE(CONVERT(NVARCHAR(20),@actual),N'NULL')+N'，入库时间'+CASE WHEN @done IS NULL THEN N'为空' ELSE N'已填' END,
 CASE WHEN @err=N'错误 54491' AND @inv1=@inv0 AND @quota1=@quota0 AND @log1=@log0 AND @aud1=@aud0
  AND @tst='pending' AND @actual IS NULL AND @done IS NULL THEN 1 ELSE 0 END);

-- R4 规则拒绝：补货量为 0 和负数、补货单不存在，都不改变库存。
DECLARE @f1 NVARCHAR(40),@f2 NVARCHAR(40),@f3 NVARCHAR(40);
SET @inv0=@inv1;
BEGIN TRY EXEC w12.usp_ReceiveRestock @task2,0,@emit_result=0; SET @f1=N'未报错'; END TRY
BEGIN CATCH SET @f1=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
BEGIN TRY EXEC w12.usp_ReceiveRestock @task2,-500,@emit_result=0; SET @f2=N'未报错'; END TRY
BEGIN CATCH SET @f2=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
BEGIN TRY EXEC w12.usp_ReceiveRestock -1,100,@emit_result=0; SET @f3=N'未报错'; END TRY
BEGIN CATCH SET @f3=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
SELECT @inv1=current_quota FROM dbo.Inventory WHERE account_id=@acct;
INSERT @r VALUES('R4',N'补货·规则拒绝',N'补货单 #'+CONVERT(NVARCHAR(11),@task2)+N' pending；库存 '+CONVERT(NVARCHAR(20),@inv0),
 N'入库数量 0、入库数量 -500、补货单 -1',N'分别返回 53303、53303、53310；库存不变；单据仍 pending',
 @f1+N'；'+@f2+N'；'+@f3+N'；库存 '+CONVERT(NVARCHAR(20),@inv1)+N'；单据 '+(SELECT status FROM dbo.RestockTask WHERE task_id=@task2),
 CASE WHEN @f1=N'错误 53303' AND @f2=N'错误 53303' AND @f3=N'错误 53310' AND @inv1=@inv0
  AND 'pending'=(SELECT status FROM dbo.RestockTask WHERE task_id=@task2) THEN 1 ELSE 0 END);

-- R5 原入口已替换：Web“完成补货”调用的 dbo.usp_W6_RestockAccount 现在委托给 w12.usp_ReceiveRestock。
SET @inv0=@inv1;
BEGIN TRY EXEC dbo.usp_W6_RestockAccount @task2,5000,@emit_result=0; SET @err=NULL; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
SELECT @inv1=current_quota FROM dbo.Inventory WHERE account_id=@acct;
INSERT @r VALUES('R5',N'补货·原入口',N'R3 回滚后的补货单 #'+CONVERT(NVARCHAR(11),@task2)+N' pending；库存 '+CONVERT(NVARCHAR(20),@inv0),
 N'EXEC dbo.usp_W6_RestockAccount '+CONVERT(NVARCHAR(11),@task2)+N',5000',N'库存 +5000；单据 completed',
 COALESCE(@err,N'库存 '+CONVERT(NVARCHAR(20),@inv0)+N'→'+CONVERT(NVARCHAR(20),@inv1)+N'；单据 '+(SELECT status FROM dbo.RestockTask WHERE task_id=@task2)),
 CASE WHEN @err IS NULL AND @inv1-@inv0=5000 AND 'completed'=(SELECT status FROM dbo.RestockTask WHERE task_id=@task2) THEN 1 ELSE 0 END);

-- 账务总检查：本次涉及账号的库存等于总额度减已用额度，余额等于未消费批次之和。
INSERT @r VALUES('Z1',N'一致性检查',N'上述用例执行完毕',N'核对补货账号与顾客 Other 余额',
 N'库存=总额度-已用；顾客 Other 余额=该顾客 Other 批次未消费合计；@@TRANCOUNT=0',
 N'库存差 '+CONVERT(NVARCHAR(20),(SELECT i.current_quota-(a.total_quota-a.used_quota) FROM dbo.Inventory i JOIN dbo.UpstreamAccount a ON a.account_id=i.account_id WHERE a.account_id=@acct))
 +N'；余额差 '+CONVERT(NVARCHAR(20),(SELECT remaining_tokens FROM dbo.TokenBalances WHERE user_id=@uid AND model_provider='Other')
  -(SELECT SUM(l.issued_tokens-l.consumed_tokens-l.refunded_tokens) FROM dbo.OrderTokenLots l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id
    JOIN dbo.Orders o ON o.order_id=d.order_id JOIN dbo.Products p ON p.product_id=d.product_id WHERE o.user_id=@uid AND p.model_provider='Other'))
 +N'；@@TRANCOUNT='+CONVERT(NVARCHAR(11),@@TRANCOUNT),
 CASE WHEN EXISTS(SELECT 1 FROM dbo.Inventory i JOIN dbo.UpstreamAccount a ON a.account_id=i.account_id WHERE a.account_id=@acct AND i.current_quota=a.total_quota-a.used_quota)
  AND (SELECT remaining_tokens FROM dbo.TokenBalances WHERE user_id=@uid AND model_provider='Other')
  =(SELECT SUM(l.issued_tokens-l.consumed_tokens-l.refunded_tokens) FROM dbo.OrderTokenLots l JOIN dbo.OrderDetails d ON d.detail_id=l.detail_id
    JOIN dbo.Orders o ON o.order_id=d.order_id JOIN dbo.Products p ON p.product_id=d.product_id WHERE o.user_id=@uid AND p.model_provider='Other')
  AND @@TRANCOUNT=0 THEN 1 ELSE 0 END);

SELECT case_no+N'|'+category+N'|'+initial+N'|'+operation+N'|'+expected+N'|'+actual+N'|'+CASE passed WHEN 1 THEN N'符合' ELSE N'不符合' END AS result_row
FROM @r ORDER BY case_no;
SELECT CONCAT(N'SUMMARY|',SUM(CONVERT(INT,passed)),N'/',COUNT(*),N'|TRANCOUNT=',@@TRANCOUNT) FROM @r;
IF EXISTS(SELECT 1 FROM @r WHERE passed=0) OR @@TRANCOUNT<>0 THROW 57900,'Week12 transaction tests failed',1;
