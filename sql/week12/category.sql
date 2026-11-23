-- 第12周商品分类层级：分类表带父级编号，商品另表挂到叶子分类。由 install.sql 安装。
CREATE SCHEMA w12 AUTHORIZATION dbo;
GO
CREATE TABLE w12.ProductCategories (
 category_id INT NOT NULL CONSTRAINT PK_W12_Categories PRIMARY KEY,
 parent_id INT NULL CONSTRAINT FK_W12_CategoryParent REFERENCES w12.ProductCategories(category_id),
 name NVARCHAR(50) NOT NULL CONSTRAINT UQ_W12_CategoryName UNIQUE,
 CONSTRAINT CK_W12_CategoryNotSelfParent CHECK (parent_id IS NULL OR parent_id<>category_id)
);
CREATE TABLE w12.ProductCategoryAssignments (
 product_id INT NOT NULL CONSTRAINT PK_W12_CategoryAssignments PRIMARY KEY
  CONSTRAINT FK_W12_AssignmentProduct REFERENCES dbo.Products(product_id) ON DELETE CASCADE,
 category_id INT NOT NULL CONSTRAINT FK_W12_AssignmentCategory REFERENCES w12.ProductCategories(category_id)
);
GO
-- 外键只保证父级存在，不能阻止 A→B→A 这样的环。插入或修改父级后，从被改的节点
-- 沿父级向上走，走回自身即为成环，整条语句回滚。上溯深度上限 32 层。
CREATE TRIGGER w12.trg_CategoryNoCycle ON w12.ProductCategories AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF NOT UPDATE(parent_id) RETURN;
 DECLARE @bad INT;
 WITH up AS (
  SELECT i.category_id start_id,i.parent_id ancestor_id,1 depth FROM inserted i WHERE i.parent_id IS NOT NULL
  UNION ALL
  SELECT up.start_id,c.parent_id,up.depth+1 FROM up JOIN w12.ProductCategories c ON c.category_id=up.ancestor_id
  WHERE c.parent_id IS NOT NULL AND up.ancestor_id<>up.start_id AND up.depth<32)
 SELECT @bad=COUNT(*) FROM up WHERE ancestor_id=start_id OR depth>=32 OPTION (MAXRECURSION 32);
 IF @bad>0 THROW 54420,'Category hierarchy would contain a cycle or exceed 32 levels',1;
END;
GO
-- 递归查询函数：返回指定分类自身及全部后代，列出编号、父级、层级与两种路径。
-- 起点：锚点成员只取 @category_id 本身；递归连接：子分类的 parent_id 等于上一层编号；
-- 终止：没有更深的子分类时停止。路径列在锚点和递归部分都显式转成 NVARCHAR(400)，
-- 并排除路径中已出现的编号，即使数据被绕过触发器写成环也不会无限递归。
CREATE FUNCTION w12.fn_CategoryDescendants(@category_id INT)
RETURNS TABLE AS RETURN
WITH tree AS (
 SELECT c.category_id,c.parent_id,c.name,0 AS level,
  CONVERT(NVARCHAR(400),N'/'+CONVERT(NVARCHAR(11),c.category_id)+N'/') AS id_path,
  CONVERT(NVARCHAR(400),c.name) AS name_path
 FROM w12.ProductCategories c WHERE c.category_id=@category_id
 UNION ALL
 SELECT c.category_id,c.parent_id,c.name,t.level+1,
  CONVERT(NVARCHAR(400),t.id_path+CONVERT(NVARCHAR(11),c.category_id)+N'/'),
  CONVERT(NVARCHAR(400),t.name_path+N' > '+c.name)
 FROM tree t JOIN w12.ProductCategories c ON c.parent_id=t.category_id
 WHERE t.id_path NOT LIKE N'%/'+CONVERT(NVARCHAR(11),c.category_id)+N'/%' AND t.level<32)
SELECT category_id,parent_id,name,level,id_path,name_path FROM tree;
GO
-- 样例层级：根 1；子 2、3；孙 4、5、6、7；OpenAI 下再分 8、9 两个叶子。
INSERT w12.ProductCategories(category_id,parent_id,name) VALUES
 (1,NULL,N'全部Token套餐'),
 (2,1,N'文本对话模型'),
 (3,1,N'多模态与其他'),
 (4,2,N'OpenAI套餐'),
 (5,2,N'Claude套餐'),
 (6,3,N'Gemini套餐'),
 (7,3,N'其他供应商套餐'),
 (8,4,N'OpenAI小容量（≤100K）'),
 (9,4,N'OpenAI大容量（>100K）');
GO
-- 安装时为已有商品建立初始映射。之后的新增和分类字段修改由商品触发器维护；
-- 删除商品时由 ProductCategoryAssignments.product_id 的 ON DELETE CASCADE 清理映射。
INSERT w12.ProductCategoryAssignments(product_id,category_id)
SELECT p.product_id,CASE p.model_provider
  WHEN 'OpenAI' THEN CASE WHEN p.token_amount<=100000 THEN 8 ELSE 9 END
  WHEN 'Claude' THEN 5 WHEN 'Gemini' THEN 6 ELSE 7 END
FROM dbo.Products p;
GO
CREATE TRIGGER dbo.trg_W12_ProductCategoryAssignments ON dbo.Products AFTER INSERT,UPDATE AS
BEGIN
 SET NOCOUNT ON;
 IF NOT EXISTS(SELECT 1 FROM inserted) RETURN;

 -- 更新已有映射：OpenAI 按 Token 容量分成两个叶子分类，其余供应商各对应一个叶子分类。
 UPDATE a SET category_id=CASE p.model_provider
   WHEN 'OpenAI' THEN CASE WHEN p.token_amount<=100000 THEN 8 ELSE 9 END
   WHEN 'Claude' THEN 5 WHEN 'Gemini' THEN 6 ELSE 7 END
 FROM w12.ProductCategoryAssignments a
 JOIN inserted p ON p.product_id=a.product_id
 WHERE a.category_id<>CASE p.model_provider
   WHEN 'OpenAI' THEN CASE WHEN p.token_amount<=100000 THEN 8 ELSE 9 END
   WHEN 'Claude' THEN 5 WHEN 'Gemini' THEN 6 ELSE 7 END;

 -- 新增商品，或修复此前缺失的映射。
 INSERT w12.ProductCategoryAssignments(product_id,category_id)
 SELECT p.product_id,CASE p.model_provider
   WHEN 'OpenAI' THEN CASE WHEN p.token_amount<=100000 THEN 8 ELSE 9 END
   WHEN 'Claude' THEN 5 WHEN 'Gemini' THEN 6 ELSE 7 END
 FROM inserted p
 WHERE NOT EXISTS(SELECT 1 FROM w12.ProductCategoryAssignments a WHERE a.product_id=p.product_id);
END;
GO
