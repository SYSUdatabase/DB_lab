/*
第三周数据库实验：数据库创建脚本（注释版）。
目标：切换到 master、创建 TokenHubDB_Week3、设置排序规则与恢复模式；数据库已存在时主动停止，避免误覆盖。
*/

-- Week 3 / 00_create_database.sql
-- Target: SQL Server 2025 Express, localhost\SQLEXPRESS
-- This script never drops an existing database automatically.

USE [master];  -- 作用：切换数据库上下文，后续语句都在这个数据库中执行
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

IF DB_ID(N'TokenHubDB_Week3') IS NULL  -- 作用：检查实验数据库是否已经存在，避免误覆盖已有数据库
BEGIN
    CREATE DATABASE [TokenHubDB_Week3]  -- 作用：创建第三周实验数据库并指定排序规则
        COLLATE Chinese_PRC_90_CI_AI_SC_UTF8;
END
ELSE
BEGIN
    THROW 50001, N'TokenHubDB_Week3 already exists. Reproduction requires an empty database.', 1;  -- 作用：数据库已存在时主动报错，阻止脚本覆盖现有实验库
END;
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO

ALTER DATABASE [TokenHubDB_Week3] SET RECOVERY SIMPLE;  -- 作用：调整实验数据库设置，使课程实验环境更易维护
-- 作用：结束当前 SQL Server 批处理，让前面的语句先完成编译与执行。
GO
