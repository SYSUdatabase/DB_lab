-- 第12周商品分类自动维护回归：验证新增、容量变更、供应商变更与删除。
-- 使用事务内临时商品，所有验证结束后回滚，不污染验收数据库。
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @tag NVARCHAR(24)=FORMAT(SYSDATETIME(),'yyyyMMddHHmmssfff');
DECLARE @openai_small INT=1,@openai_large INT=100001,@claude_tokens INT=1,
        @gemini_tokens INT=1,@other_tokens INT=1;
WHILE EXISTS(SELECT 1 FROM dbo.Products WHERE model_provider='OpenAI' AND token_amount=@openai_small)
 AND @openai_small<100000 SET @openai_small+=1;
WHILE EXISTS(SELECT 1 FROM dbo.Products WHERE model_provider='OpenAI' AND token_amount=@openai_large)
 AND @openai_large<2147483647 SET @openai_large+=1;
WHILE EXISTS(SELECT 1 FROM dbo.Products WHERE model_provider='Claude' AND token_amount=@claude_tokens)
 AND @claude_tokens<2147483647 SET @claude_tokens+=1;
WHILE EXISTS(SELECT 1 FROM dbo.Products WHERE model_provider='Gemini' AND token_amount=@gemini_tokens)
 AND @gemini_tokens<2147483647 SET @gemini_tokens+=1;
WHILE EXISTS(SELECT 1 FROM dbo.Products WHERE model_provider='Other' AND token_amount=@other_tokens)
 AND @other_tokens<2147483647 SET @other_tokens+=1;
IF EXISTS(SELECT 1 FROM dbo.Products WHERE model_provider='OpenAI' AND token_amount=@openai_small)
 OR EXISTS(SELECT 1 FROM dbo.Products WHERE model_provider='OpenAI' AND token_amount=@openai_large)
 OR EXISTS(SELECT 1 FROM dbo.Products WHERE model_provider='Claude' AND token_amount=@claude_tokens)
 OR EXISTS(SELECT 1 FROM dbo.Products WHERE model_provider='Gemini' AND token_amount=@gemini_tokens)
 OR EXISTS(SELECT 1 FROM dbo.Products WHERE model_provider='Other' AND token_amount=@other_tokens)
 THROW 57901,'Could not allocate unique category test token amounts',1;
IF @openai_small>100000 THROW 57901,'No OpenAI token amount remains in the small category range',1;

DECLARE @pid INT,@actual INT,@leaf INT,@product_rows INT,@assignment_rows INT;
DECLARE @actual1 INT,@actual2 INT,@actual3 INT,@actual4 INT,@actual5 INT;
DECLARE @leaf1 INT,@leaf2 INT,@leaf3 INT,@leaf4 INT,@leaf5 INT;
BEGIN TRY
 BEGIN TRANSACTION;

 -- C1 新增 OpenAI 小容量商品后自动挂到分类 8，递归函数可返回该分类。
 INSERT dbo.Products(name,description,price,model_provider,token_amount,required_upstream_tokens,status)
 VALUES(N'W12分类自动维护_'+@tag,N'自动分类回归',1.00,'OpenAI',@openai_small,1,'inactive');
 SET @pid=CONVERT(INT,SCOPE_IDENTITY());
 SELECT @actual1=a.category_id
 FROM w12.ProductCategoryAssignments a
 JOIN w12.fn_CategoryDescendants(1) t ON t.category_id=a.category_id
 WHERE a.product_id=@pid;
 SELECT @leaf1=CASE WHEN @actual1 IS NOT NULL AND NOT EXISTS(
  SELECT 1 FROM w12.ProductCategories c WHERE c.parent_id=@actual1) THEN 1 ELSE 0 END;

 -- C2 修改 Token 容量越过 100K 阈值，映射从分类 8 自动迁移到分类 9。
 UPDATE dbo.Products SET token_amount=@openai_large WHERE product_id=@pid;
 SELECT @actual2=a.category_id
 FROM w12.ProductCategoryAssignments a
 JOIN w12.fn_CategoryDescendants(1) t ON t.category_id=a.category_id
 WHERE a.product_id=@pid;
 SELECT @leaf2=CASE WHEN @actual2 IS NOT NULL AND NOT EXISTS(
  SELECT 1 FROM w12.ProductCategories c WHERE c.parent_id=@actual2) THEN 1 ELSE 0 END;

 -- C3—C5 修改供应商，映射依次更新到 Claude、Gemini、Other 对应的叶子分类。
 UPDATE dbo.Products SET model_provider='Claude',token_amount=@claude_tokens WHERE product_id=@pid;
 SELECT @actual3=a.category_id
 FROM w12.ProductCategoryAssignments a
 JOIN w12.fn_CategoryDescendants(1) t ON t.category_id=a.category_id
 WHERE a.product_id=@pid;
 SELECT @leaf3=CASE WHEN @actual3 IS NOT NULL AND NOT EXISTS(
  SELECT 1 FROM w12.ProductCategories c WHERE c.parent_id=@actual3) THEN 1 ELSE 0 END;

 UPDATE dbo.Products SET model_provider='Gemini',token_amount=@gemini_tokens WHERE product_id=@pid;
 SELECT @actual4=a.category_id
 FROM w12.ProductCategoryAssignments a
 JOIN w12.fn_CategoryDescendants(1) t ON t.category_id=a.category_id
 WHERE a.product_id=@pid;
 SELECT @leaf4=CASE WHEN @actual4 IS NOT NULL AND NOT EXISTS(
  SELECT 1 FROM w12.ProductCategories c WHERE c.parent_id=@actual4) THEN 1 ELSE 0 END;

 UPDATE dbo.Products SET model_provider='Other',token_amount=@other_tokens WHERE product_id=@pid;
 SELECT @actual5=a.category_id
 FROM w12.ProductCategoryAssignments a
 JOIN w12.fn_CategoryDescendants(1) t ON t.category_id=a.category_id
 WHERE a.product_id=@pid;
 SELECT @leaf5=CASE WHEN @actual5 IS NOT NULL AND NOT EXISTS(
  SELECT 1 FROM w12.ProductCategories c WHERE c.parent_id=@actual5) THEN 1 ELSE 0 END;

 -- C6 删除商品后，级联外键自动清除分类映射，不留下孤立记录。
 DELETE dbo.Products WHERE product_id=@pid;
 SELECT @product_rows=COUNT(*) FROM dbo.Products WHERE product_id=@pid;
 SELECT @assignment_rows=COUNT(*) FROM w12.ProductCategoryAssignments WHERE product_id=@pid;

 ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;

DECLARE @r TABLE(case_no VARCHAR(8),scenario NVARCHAR(60),expected NVARCHAR(160),actual NVARCHAR(160),passed BIT);
INSERT @r VALUES
 ('C1',N'新增商品自动分类',N'OpenAI 小容量→分类 8，递归可见且为叶子',
  N'category_id='+COALESCE(CONVERT(NVARCHAR(11),@actual1),N'NULL')+N'；leaf='+COALESCE(CONVERT(NVARCHAR(1),@leaf1),N'NULL'),
  CASE WHEN @actual1=8 AND @leaf1=1 THEN 1 ELSE 0 END),
 ('C2',N'容量变化自动重分类',N'OpenAI 大容量→分类 9，递归可见且为叶子',
  N'category_id='+COALESCE(CONVERT(NVARCHAR(11),@actual2),N'NULL')+N'；leaf='+COALESCE(CONVERT(NVARCHAR(1),@leaf2),N'NULL'),
  CASE WHEN @actual2=9 AND @leaf2=1 THEN 1 ELSE 0 END),
 ('C3',N'供应商变更为 Claude',N'Claude→分类 5，递归可见且为叶子',
  N'category_id='+COALESCE(CONVERT(NVARCHAR(11),@actual3),N'NULL')+N'；leaf='+COALESCE(CONVERT(NVARCHAR(1),@leaf3),N'NULL'),
  CASE WHEN @actual3=5 AND @leaf3=1 THEN 1 ELSE 0 END),
 ('C4',N'供应商变更为 Gemini',N'Gemini→分类 6，递归可见且为叶子',
  N'category_id='+COALESCE(CONVERT(NVARCHAR(11),@actual4),N'NULL')+N'；leaf='+COALESCE(CONVERT(NVARCHAR(1),@leaf4),N'NULL'),
  CASE WHEN @actual4=6 AND @leaf4=1 THEN 1 ELSE 0 END),
 ('C5',N'供应商变更为 Other',N'Other→分类 7，递归可见且为叶子',
  N'category_id='+COALESCE(CONVERT(NVARCHAR(11),@actual5),N'NULL')+N'；leaf='+COALESCE(CONVERT(NVARCHAR(1),@leaf5),N'NULL'),
  CASE WHEN @actual5=7 AND @leaf5=1 THEN 1 ELSE 0 END),
 ('C6',N'删除商品级联清理',N'商品与分类映射均不存在',
  N'product_rows='+CONVERT(NVARCHAR(11),@product_rows)+N'；assignment_rows='+CONVERT(NVARCHAR(11),@assignment_rows),
  CASE WHEN @product_rows=0 AND @assignment_rows=0 THEN 1 ELSE 0 END);

SELECT case_no+N'|'+scenario+N'|'+expected+N'|'+actual+N'|'+
 CASE passed WHEN 1 THEN N'符合' ELSE N'不符合' END AS result_row
FROM @r ORDER BY case_no;
SELECT CONCAT(N'SUMMARY|',SUM(CONVERT(INT,passed)),N'/',COUNT(*),N'|TRANCOUNT=',@@TRANCOUNT) FROM @r;
IF EXISTS(SELECT 1 FROM @r WHERE passed=0) OR @@TRANCOUNT<>0
 THROW 57902,'Week12 category maintenance tests failed',1;
