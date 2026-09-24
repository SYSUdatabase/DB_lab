USE TokenHubDB_Week3;
GO

INSERT INTO dbo.Products
(name, price, model_provider, token_amount, required_upstream_tokens, status)
VALUES (N'非法价格测试', -1.00, 'Other', 1, 1, 'active');
GO

INSERT INTO dbo.Orders (user_id, total_amount, total_tokens, status)
VALUES (999999, 1.00, 1, 'pending');
GO