-- 只对独立的第13周 Web 批次执行，初次创建实验对象。
SET XACT_ABORT ON;
IF DB_NAME() NOT LIKE N'TokenHubDB[_]v11[_]WebW13%' OR SCHEMA_ID('w12') IS NULL
 THROW 57100,'Use a dedicated WebW13 batch with week 12 installed',1;
IF SCHEMA_ID('w13lab') IS NOT NULL THROW 57101,'Lab already initialized',1;
BEGIN TRAN;
EXEC(N'CREATE SCHEMA w13lab AUTHORIZATION dbo');
CREATE TABLE w13lab.Stock (product_id int PRIMARY KEY, code char(1) UNIQUE,
 quantity int NOT NULL CHECK(quantity>=0));
CREATE TABLE w13lab.OrderCase (id int PRIMARY KEY, status varchar(12) NOT NULL);
CREATE TABLE w13lab.RestockCase (id int PRIMARY KEY, status varchar(12) NOT NULL, actual int NULL);
INSERT w13lab.Stock VALUES(1,'P',10),(2,'Q',8);
INSERT w13lab.OrderCase VALUES(1,'pending');
INSERT w13lab.RestockCase VALUES(1,'pending',NULL);
COMMIT;
