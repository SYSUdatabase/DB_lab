-- 第11周触发器测试：单条插入、单条修改、多条修改、正常操作、非法数据和触发器拒绝。
-- 在安装了第11周扩展的专用实验库上执行。每次运行用当时的时间生成新的测试账号、商品和订单，
-- 互不干扰，相当于每次从重置后的数据开始；需要回滚的用例在用例内部开启并回滚事务。
-- 最后一个结果集按“编号|类别|初始数据|操作|预期结果|实际结果|是否符合”输出。
-- sqlcmd 默认关闭 QUOTED_IDENTIFIER；写入带筛选索引的表和调用过程前统一打开。
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;
DECLARE @r TABLE(case_no VARCHAR(8),category NVARCHAR(20),initial NVARCHAR(400),operation NVARCHAR(400),
 expected NVARCHAR(400),actual NVARCHAR(400),passed BIT);
DECLARE @tag VARCHAR(12)=FORMAT(SYSDATETIME(),'MMddHHmmss'),@now DATETIME2(0)=CONVERT(DATETIME2(0),SYSDATETIME());
DECLARE @a1 INT,@a2 INT,@inv1 INT,@inv2 INT,@q1 BIGINT,@q2 BIGINT,@n0 INT,@n1 INT,@err NVARCHAR(400),
 @before BIGINT,@after BIGINT,@op NVARCHAR(128),@type VARCHAR(10),@uid INT,@p INT,@q INT,@big INT,
 @o1 INT,@o2 INT,@o3 INT,@st VARCHAR(24),@st2 VARCHAR(24),@admin INT;
SELECT @uid=user_id FROM dbo.Users WHERE username='web_customer';
SELECT @admin=e.employee_id FROM dbo.Employees e JOIN dbo.Roles r ON r.role_id=e.role_id
 WHERE e.account='web_admin' AND r.role_name='admin';

-- A1 单条插入：新建上游账号时 trg_W5_AutoInventoryOnAccount 插入一行库存，审计记 insert。
SELECT @n0=COUNT(*) FROM w11.InventoryAudit;
INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,used_quota,safety_threshold,status,expires_at)
VALUES('Other',N'W11审计账号A_'+@tag,N'sk-w11-a-'+@tag,500000,0,1000,'active','20271231');
SET @a1=SCOPE_IDENTITY();
SELECT @inv1=inventory_id FROM dbo.Inventory WHERE account_id=@a1;
SELECT @n1=COUNT(*) FROM w11.InventoryAudit;
SELECT @type=operation_type,@before=quota_before,@after=quota_after,@op=operator FROM w11.InventoryAudit
 WHERE inventory_id=@inv1 AND operation_type='insert';
INSERT @r VALUES('A1',N'单条插入',N'审计表 '+CONVERT(NVARCHAR(20),@n0)+N' 行',
 N'新建 Other 账号 #'+CONVERT(NVARCHAR(11),@a1)+N'，总额度 500000',
 N'新增 1 行审计：insert，调整前 NULL，调整后 500000',
 N'新增 '+CONVERT(NVARCHAR(11),@n1-@n0)+N' 行：'+COALESCE(@type,N'无')+N'，调整前 '+COALESCE(CONVERT(NVARCHAR(20),@before),N'NULL')
 +N'，调整后 '+COALESCE(CONVERT(NVARCHAR(20),@after),N'NULL')+N'，操作人 '+COALESCE(@op,N'无'),
 CASE WHEN @n1-@n0=1 AND @type='insert' AND @before IS NULL AND @after=500000 THEN 1 ELSE 0 END);

-- A2 单条修改（正常业务）：管理员经第10周库存调整过程 +3000，审计记 increase，操作人取会话上下文。
INSERT dbo.UpstreamAccount(provider,account_name,api_key,total_quota,used_quota,safety_threshold,status,expires_at)
VALUES('Other',N'W11审计账号B_'+@tag,N'sk-w11-b-'+@tag,800000,0,1000,'active','20271231');
SET @a2=SCOPE_IDENTITY();
SELECT @inv2=inventory_id FROM dbo.Inventory WHERE account_id=@a2;
SELECT TOP (1) @p=product_id FROM dbo.Products WHERE model_provider='Other' ORDER BY product_id;
IF @p IS NULL
BEGIN
 INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status)
 VALUES(N'W11审计商品_'+@tag,N'第11周测试商品',5.00,'Other',30000+CONVERT(INT,RIGHT(@tag,4)),30000+CONVERT(INT,RIGHT(@tag,4)),'active');
 SET @p=SCOPE_IDENTITY();
END;
SELECT @q1=current_quota FROM dbo.Inventory WHERE inventory_id=@inv1;
SELECT @n0=COUNT(*) FROM w11.InventoryAudit;
DECLARE @key UNIQUEIDENTIFIER=NEWID();
EXEC sys.sp_set_session_context @key=N'tokenhub.actor',@value=N'employee:test-admin';
BEGIN TRY
 EXEC w10.usp_AdjustInventory @product_id=@p,@account_id=@a1,@change_amount=3000,
  @reason=N'第11周审计测试：单条增加',@operator_id=@admin,@operation_key=@key,@emit_result=0;
 SET @err=NULL;
END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER(),N' ',ERROR_MESSAGE()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
EXEC sys.sp_set_session_context @key=N'tokenhub.actor',@value=NULL;
SELECT @n1=COUNT(*) FROM w11.InventoryAudit;
SELECT TOP (1) @type=operation_type,@before=quota_before,@after=quota_after,@op=operator FROM w11.InventoryAudit
 WHERE inventory_id=@inv1 ORDER BY audit_id DESC;
INSERT @r VALUES('A2',N'单条修改',N'账号 #'+CONVERT(NVARCHAR(11),@a1)+N' 库存 '+CONVERT(NVARCHAR(20),@q1),
 N'以 employee:test-admin 身份调用 w10.usp_AdjustInventory +3000',
 N'新增 1 行：increase，'+CONVERT(NVARCHAR(20),@q1)+N'→'+CONVERT(NVARCHAR(20),@q1+3000)+N'，操作人 employee:test-admin',
 COALESCE(@err,N'新增 '+CONVERT(NVARCHAR(11),@n1-@n0)+N' 行：'+@type+N'，'+CONVERT(NVARCHAR(20),@before)+N'→'+CONVERT(NVARCHAR(20),@after)+N'，操作人 '+@op),
 CASE WHEN @err IS NULL AND @n1-@n0=1 AND @type='increase' AND @before=@q1 AND @after=@q1+3000 AND @op=N'employee:test-admin' THEN 1 ELSE 0 END);

-- A3 多条修改：一条 UPDATE 同时减少两个账号的库存，审计应逐行记 2 条。同一事务内同步减少总额度、
-- 写入 manual 调整流水，保持“库存=总额度-已用”和“库存变动都有流水”两条账务规则。
SELECT @q1=current_quota FROM dbo.Inventory WHERE inventory_id=@inv1;
SELECT @q2=current_quota FROM dbo.Inventory WHERE inventory_id=@inv2;
SELECT @n0=COUNT(*) FROM w11.InventoryAudit;
BEGIN TRY
 BEGIN TRANSACTION;
 UPDATE dbo.UpstreamAccount SET total_quota=total_quota-200 WHERE account_id IN(@a1,@a2);
 UPDATE dbo.Inventory SET current_quota=current_quota-200,last_updated_at=SYSDATETIME() WHERE account_id IN(@a1,@a2);
 INSERT dbo.InventoryLog(account_id,change_type,change_amount,reference_type,reference_id,reason,operator_id,created_at)
 SELECT v.account_id,'adjustment',-200,'manual',NULL,N'第11周审计测试：多行减少',@admin,SYSDATETIME()
 FROM (VALUES(@a1),(@a2)) v(account_id);
 COMMIT;
 SET @err=NULL;
END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER(),N' ',ERROR_MESSAGE()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
SELECT @n1=COUNT(*) FROM w11.InventoryAudit;
INSERT @r VALUES('A3',N'多条修改',
 N'账号 #'+CONVERT(NVARCHAR(11),@a1)+N' 库存 '+CONVERT(NVARCHAR(20),@q1)+N'，账号 #'+CONVERT(NVARCHAR(11),@a2)+N' 库存 '+CONVERT(NVARCHAR(20),@q2),
 N'一条 UPDATE 把两行库存各减 200',
 N'新增 2 行 decrease，变化量均为 -200，调整前后分别对应各自账号',
 COALESCE(@err,N'新增 '+CONVERT(NVARCHAR(11),@n1-@n0)+N' 行：'+(SELECT STRING_AGG(CONCAT(N'#',account_id,N' ',operation_type,N' ',quota_before,N'→',quota_after,N'（',change_quantity,N'）'),N'；')
  WITHIN GROUP (ORDER BY account_id) FROM w11.InventoryAudit WHERE audit_id>(SELECT MAX(audit_id)-(@n1-@n0) FROM w11.InventoryAudit))),
 CASE WHEN @err IS NULL AND @n1-@n0=2 AND 2=(SELECT COUNT(*) FROM (SELECT TOP (2) * FROM w11.InventoryAudit ORDER BY audit_id DESC) x
  WHERE x.operation_type='decrease' AND x.change_quantity=-200
  AND ((x.account_id=@a1 AND x.quota_before=@q1) OR (x.account_id=@a2 AND x.quota_before=@q2))) THEN 1 ELSE 0 END);

-- A4 数量不变的修改：只改 last_updated_at，不应产生审计。
SELECT @n0=COUNT(*) FROM w11.InventoryAudit;
UPDATE dbo.Inventory SET last_updated_at=SYSDATETIME() WHERE account_id IN(@a1,@a2);
SELECT @n1=COUNT(*) FROM w11.InventoryAudit;
INSERT @r VALUES('A4',N'正常操作',N'审计表 '+CONVERT(NVARCHAR(20),@n0)+N' 行',N'两行库存只更新时间、数量不变',
 N'不新增审计记录',N'新增 '+CONVERT(NVARCHAR(11),@n1-@n0)+N' 行',CASE WHEN @n1=@n0 THEN 1 ELSE 0 END);

-- A5 非法数据：把库存改成负数，被 CHECK 约束拒绝，审计随语句一起回滚。
SELECT @q1=current_quota FROM dbo.Inventory WHERE inventory_id=@inv1;
SELECT @n0=COUNT(*) FROM w11.InventoryAudit;
BEGIN TRY
 UPDATE dbo.Inventory SET current_quota=-1 WHERE account_id=@a1;
 SET @err=N'未报错';
END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
SELECT @n1=COUNT(*) FROM w11.InventoryAudit;
INSERT @r VALUES('A5',N'非法数据',N'账号 #'+CONVERT(NVARCHAR(11),@a1)+N' 库存 '+CONVERT(NVARCHAR(20),@q1),
 N'UPDATE 库存为 -1',N'约束拒绝（547），库存不变，审计不新增',
 @err+N'，库存 '+CONVERT(NVARCHAR(20),(SELECT current_quota FROM dbo.Inventory WHERE inventory_id=@inv1))+N'，审计新增 '+CONVERT(NVARCHAR(11),@n1-@n0),
 CASE WHEN @err=N'错误 547' AND @n1=@n0 AND @q1=(SELECT current_quota FROM dbo.Inventory WHERE inventory_id=@inv1) THEN 1 ELSE 0 END);

-- A6 触发器拒绝：审计记录只允许追加，修改被 w11.trg_InventoryAuditImmutable 拒绝。
BEGIN TRY
 UPDATE w11.InventoryAudit SET operator=N'tamper' WHERE inventory_id=@inv1;
 SET @err=N'未报错';
END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
INSERT @r VALUES('A6',N'触发器拒绝',N'账号 #'+CONVERT(NVARCHAR(11),@a1)+N' 已有审计记录',N'UPDATE 审计表的操作人字段',
 N'拒绝（54409），记录不变',@err+N'，被改记录 '+CONVERT(NVARCHAR(11),(SELECT COUNT(*) FROM w11.InventoryAudit WHERE operator=N'tamper'))+N' 行',
 CASE WHEN @err=N'错误 54409' AND NOT EXISTS(SELECT 1 FROM w11.InventoryAudit WHERE operator=N'tamper') THEN 1 ELSE 0 END);

-- 订单完成规则用的测试商品：普通商品 P、Q，以及一份超过 Other 全部可售余量的大套餐。
INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status)
VALUES(N'W11商品P_'+@tag,N'第11周测试商品P',12.00,'Other',100000+CONVERT(INT,RIGHT(@tag,5)),100000+CONVERT(INT,RIGHT(@tag,5)),'active');
SET @p=SCOPE_IDENTITY();
INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status)
VALUES(N'W11商品Q_'+@tag,N'第11周测试商品Q',8.00,'Other',200000+CONVERT(INT,RIGHT(@tag,5)),200000+CONVERT(INT,RIGHT(@tag,5)),'active');
SET @q=SCOPE_IDENTITY();
INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status)
VALUES(N'W11超量套餐_'+@tag,N'第11周库存不足测试',1.00,'Other',2000000000-CONVERT(INT,RIGHT(@tag,5)),2000000000-CONVERT(INT,RIGHT(@tag,5)),'active');
SET @big=SCOPE_IDENTITY();

-- O1 正常完成：P×2、Q×1 的待支付订单经完成事务改为 paid，触发器放行。
EXEC dbo.usp_W5_CreateRegisteredOrder @uid,@emit_result=0,@app_result_id=@o1 OUTPUT;
EXEC dbo.usp_W5_AddMergedOrderItem @o1,@p,2,@emit_result=0;
EXEC dbo.usp_W5_AddMergedOrderItem @o1,@q,1,@emit_result=0;
BEGIN TRY EXEC w12.usp_CompleteOrder @o1,@emit_result=0; SET @err=NULL; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER(),N' ',ERROR_MESSAGE()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
SELECT @st=status FROM dbo.Orders WHERE order_id=@o1;
INSERT @r VALUES('O1',N'正常操作',N'订单 #'+CONVERT(NVARCHAR(11),@o1)+N' pending，明细 P×2、Q×1',N'调用订单完成事务（状态改为 paid）',
 N'触发器放行，状态 paid',COALESCE(@err,N'状态 '+@st),CASE WHEN @err IS NULL AND @st='paid' THEN 1 ELSE 0 END);

-- O2 重复完成：对已完成订单再次 UPDATE status='paid'。
BEGIN TRY UPDATE dbo.Orders SET status='paid' WHERE order_id=@o1; SET @err=N'未报错'; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
INSERT @r VALUES('O2',N'触发器拒绝',N'订单 #'+CONVERT(NVARCHAR(11),@o1)+N' 已为 paid',N'UPDATE 状态再次设为 paid',
 N'拒绝（54401），状态仍为 paid',@err+N'，状态 '+(SELECT status FROM dbo.Orders WHERE order_id=@o1),
 CASE WHEN @err=N'错误 54401' THEN 1 ELSE 0 END);

-- O3 无明细：空的待支付订单直接改为 paid。
EXEC dbo.usp_W5_CreateRegisteredOrder @uid,@emit_result=0,@app_result_id=@o2 OUTPUT;
BEGIN TRY UPDATE dbo.Orders SET status='paid',paid_at=SYSDATETIME() WHERE order_id=@o2; SET @err=N'未报错'; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
INSERT @r VALUES('O3',N'非法数据',N'订单 #'+CONVERT(NVARCHAR(11),@o2)+N' pending，无明细',N'UPDATE 状态为 paid',
 N'拒绝（54403），状态仍为 pending',@err+N'，状态 '+(SELECT status FROM dbo.Orders WHERE order_id=@o2),
 CASE WHEN @err=N'错误 54403' AND 'pending'=(SELECT status FROM dbo.Orders WHERE order_id=@o2) THEN 1 ELSE 0 END);

-- O4 金额不符：把订单金额改得与明细合计不一致，同时改为 paid。
EXEC dbo.usp_W5_CreateRegisteredOrder @uid,@emit_result=0,@app_result_id=@o3 OUTPUT;
EXEC dbo.usp_W5_AddMergedOrderItem @o3,@p,1,@emit_result=0;
BEGIN TRY UPDATE dbo.Orders SET total_amount=total_amount+1,status='paid',paid_at=SYSDATETIME() WHERE order_id=@o3; SET @err=N'未报错'; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
INSERT @r VALUES('O4',N'非法数据',N'订单 #'+CONVERT(NVARCHAR(11),@o3)+N' pending，P×1，金额 '+CONVERT(NVARCHAR(20),(SELECT total_amount FROM dbo.Orders WHERE order_id=@o3)),
 N'UPDATE 金额 +1 元并改为 paid',N'拒绝（54405），金额与状态不变',
 @err+N'，状态 '+(SELECT status FROM dbo.Orders WHERE order_id=@o3)+N'，金额 '+CONVERT(NVARCHAR(20),(SELECT total_amount FROM dbo.Orders WHERE order_id=@o3)),
 CASE WHEN @err=N'错误 54405' AND 'pending'=(SELECT status FROM dbo.Orders WHERE order_id=@o3) THEN 1 ELSE 0 END);

-- O5 库存不足：订单需求超过 Other 供应商的可售余量。
DECLARE @o4 INT,@sell DECIMAL(38,0);
EXEC dbo.usp_W5_CreateRegisteredOrder @uid,@emit_result=0,@app_result_id=@o4 OUTPUT;
EXEC dbo.usp_W5_AddMergedOrderItem @o4,@big,1,@emit_result=0;
SELECT @sell=available_quota-outstanding_upstream FROM w11.fn_ProviderSellable('Other');
BEGIN TRY UPDATE dbo.Orders SET status='paid',paid_at=SYSDATETIME() WHERE order_id=@o4; SET @err=N'未报错'; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
INSERT @r VALUES('O5',N'触发器拒绝',N'订单 #'+CONVERT(NVARCHAR(11),@o4)+N' 上游需求 '+CONVERT(NVARCHAR(20),(SELECT SUM(d.quantity*CONVERT(BIGINT,p.required_upstream_tokens)) FROM dbo.OrderDetails d JOIN dbo.Products p ON p.product_id=d.product_id WHERE d.order_id=@o4))
 +N'，Other 可售上游余量 '+CONVERT(NVARCHAR(40),@sell),N'UPDATE 状态为 paid',N'拒绝（54406），状态仍为 pending',
 @err+N'，状态 '+(SELECT status FROM dbo.Orders WHERE order_id=@o4),
 CASE WHEN @err=N'错误 54406' AND 'pending'=(SELECT status FROM dbo.Orders WHERE order_id=@o4) THEN 1 ELSE 0 END);

-- O6 多条修改含不合格行：一条 UPDATE 同时完成 O3（合格）与 O2（无明细），整条语句被拒绝。
BEGIN TRY UPDATE dbo.Orders SET status='paid',paid_at=SYSDATETIME() WHERE order_id IN(@o2,@o3); SET @err=N'未报错'; END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
SELECT @st=status FROM dbo.Orders WHERE order_id=@o3; SELECT @st2=status FROM dbo.Orders WHERE order_id=@o2;
INSERT @r VALUES('O6',N'多条修改',N'订单 #'+CONVERT(NVARCHAR(11),@o3)+N'（有明细）与 #'+CONVERT(NVARCHAR(11),@o2)+N'（无明细）均为 pending',
 N'一条 UPDATE 同时改为 paid',N'整条拒绝（54403），两单都仍为 pending',@err+N'，状态 '+@st+N' / '+@st2,
 CASE WHEN @err=N'错误 54403' AND @st='pending' AND @st2='pending' THEN 1 ELSE 0 END);

-- O7 多条修改全部合格：两张有明细的订单一条 UPDATE 改为 paid，触发器逐单检查后放行；
-- 直接改状态会绕过余额发放，验证后回滚，只观察触发器的多行处理。
DECLARE @o5 INT;
EXEC dbo.usp_W5_CreateRegisteredOrder @uid,@emit_result=0,@app_result_id=@o5 OUTPUT;
EXEC dbo.usp_W5_AddMergedOrderItem @o5,@q,1,@emit_result=0;
BEGIN TRY
 BEGIN TRANSACTION;
 UPDATE dbo.Orders SET status='paid',paid_at=SYSDATETIME() WHERE order_id IN(@o3,@o5);
 SET @n1=@@ROWCOUNT;
 ROLLBACK;
 SET @err=NULL;
END TRY
BEGIN CATCH SET @err=CONCAT(N'错误 ',ERROR_NUMBER()); IF XACT_STATE()<>0 ROLLBACK; END CATCH;
INSERT @r VALUES('O7',N'多条修改',N'订单 #'+CONVERT(NVARCHAR(11),@o3)+N'、#'+CONVERT(NVARCHAR(11),@o5)+N' 均有明细、金额一致',
 N'事务内一条 UPDATE 同时改为 paid，随后回滚',N'触发器放行 2 行；回滚后仍为 pending',
 COALESCE(@err,N'更新 '+CONVERT(NVARCHAR(11),@n1)+N' 行；回滚后 '+(SELECT status FROM dbo.Orders WHERE order_id=@o3)+N' / '+(SELECT status FROM dbo.Orders WHERE order_id=@o5)),
 CASE WHEN @err IS NULL AND @n1=2 AND 'pending'=(SELECT status FROM dbo.Orders WHERE order_id=@o5) THEN 1 ELSE 0 END);

-- 结果记录：本次测试账号的全部库存审计记录与测试订单的最终状态（列之间用 | 分隔）。
PRINT N'== 库存审计记录：audit_id|account_id|provider|operation_type|quota_before|quota_after|change_quantity|operated_at|operator';
SELECT CONCAT_WS(N'|',audit_id,account_id,provider,operation_type,COALESCE(CONVERT(NVARCHAR(20),quota_before),N'NULL'),
 COALESCE(CONVERT(NVARCHAR(20),quota_after),N'NULL'),change_quantity,CONVERT(NVARCHAR(23),operated_at,121),operator)
FROM w11.InventoryAudit WHERE account_id IN(@a1,@a2) ORDER BY audit_id;
PRINT N'== 测试订单状态：order_id|status|total_amount|total_tokens|paid_at';
SELECT CONCAT_WS(N'|',order_id,status,total_amount,total_tokens,COALESCE(CONVERT(NVARCHAR(19),paid_at,120),N'NULL'))
FROM dbo.Orders WHERE order_id IN(@o1,@o2,@o3,@o4,@o5) ORDER BY order_id;
PRINT N'== 用例结果：编号|类别|初始数据|操作|预期结果|实际结果|是否符合';
SELECT case_no+N'|'+category+N'|'+initial+N'|'+operation+N'|'+expected+N'|'+actual+N'|'+CASE passed WHEN 1 THEN N'符合' ELSE N'不符合' END AS result_row
FROM @r ORDER BY case_no;
SELECT CONCAT(N'SUMMARY|',SUM(CONVERT(INT,passed)),N'/',COUNT(*),N'|TRANCOUNT=',@@TRANCOUNT) FROM @r;
IF EXISTS(SELECT 1 FROM @r WHERE passed=0) OR @@TRANCOUNT<>0 THROW 57900,'Week11 trigger tests failed',1;
