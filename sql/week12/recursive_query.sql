-- 第12周层级递归查询。只读，安装第12周扩展（sql/week12/install.sql）后可反复执行。
--
-- 层级结构：w12.ProductCategories(category_id, parent_id, name)，parent_id 引用本表，
-- 根节点 parent_id 为 NULL；商品通过 w12.ProductCategoryAssignments 挂到叶子分类。
-- 外键只保证父级存在，防环由触发器 w12.trg_CategoryNoCycle 负责（见 category.sql）。
--
-- 样例关系（编号 名称 ← 父级）：
--   1 全部Token套餐（根）
--   ├─ 2 文本对话模型 ← 1
--   │   ├─ 4 OpenAI套餐 ← 2
--   │   │   ├─ 8 OpenAI小容量（≤100K） ← 4
--   │   │   └─ 9 OpenAI大容量（>100K） ← 4
--   │   └─ 5 Claude套餐 ← 2
--   └─ 3 多模态与其他 ← 1（另一条分支）
--       ├─ 6 Gemini套餐 ← 3
--       └─ 7 其他供应商套餐 ← 3
SET NOCOUNT ON;

PRINT N'== 样例数据：分类表与各叶子分类下的商品数';
SELECT c.category_id,c.parent_id,c.name,
 (SELECT COUNT(*) FROM w12.ProductCategoryAssignments a WHERE a.category_id=c.category_id) product_count
FROM w12.ProductCategories c ORDER BY c.category_id;

-- 递归 CTE 本体（与 w12.fn_CategoryDescendants 相同）：
--   起点     锚点成员只取指定编号本身，层级 0；
--   递归连接 子分类 parent_id = 上一层 category_id，层级 +1，路径追加本节点；
--   终止条件 没有更深的子分类；另排除路径中已出现的编号并限制 32 层，
--            OPTION (MAXRECURSION 32) 作为语句级上限。
-- 路径列在锚点与递归部分都转换为 NVARCHAR(400)，类型与长度一致。
DECLARE @cases TABLE(case_no INT, label NVARCHAR(20), category_id INT);
INSERT @cases VALUES (1,N'根节点',1),(2,N'中间节点',2),(3,N'叶子节点',8),(4,N'不存在的编号',999);
DECLARE @no INT=1,@label NVARCHAR(20),@id INT;
WHILE @no<=4
BEGIN
 SELECT @label=label,@id=category_id FROM @cases WHERE case_no=@no;
 PRINT N'== '+@label+N'：category_id='+CONVERT(NVARCHAR(11),@id);
 WITH tree AS (
  SELECT c.category_id,c.parent_id,c.name,0 AS level,
   CONVERT(NVARCHAR(400),N'/'+CONVERT(NVARCHAR(11),c.category_id)+N'/') AS id_path,
   CONVERT(NVARCHAR(400),c.name) AS name_path
  FROM w12.ProductCategories c WHERE c.category_id=@id
  UNION ALL
  SELECT c.category_id,c.parent_id,c.name,t.level+1,
   CONVERT(NVARCHAR(400),t.id_path+CONVERT(NVARCHAR(11),c.category_id)+N'/'),
   CONVERT(NVARCHAR(400),t.name_path+N' > '+c.name)
  FROM tree t JOIN w12.ProductCategories c ON c.parent_id=t.category_id
  WHERE t.id_path NOT LIKE N'%/'+CONVERT(NVARCHAR(11),c.category_id)+N'/%' AND t.level<32)
 SELECT category_id,parent_id,level,id_path,name_path FROM tree
 ORDER BY id_path OPTION (MAXRECURSION 32);
 IF @@ROWCOUNT=0 PRINT N'结果为空：分类不存在';
 SET @no+=1;
END;

PRINT N'== 某分类及其全部后代下的商品（以中间节点 2 为例，经函数调用）';
SELECT t.category_id,t.level,t.name_path,p.product_id,p.name product_name
FROM w12.fn_CategoryDescendants(2) t
JOIN w12.ProductCategoryAssignments a ON a.category_id=t.category_id
JOIN dbo.Products p ON p.product_id=a.product_id
ORDER BY t.id_path,p.product_id OPTION (MAXRECURSION 32);
