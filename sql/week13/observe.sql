-- 在可查看实例 DMV 的观察连接执行。若无权限，请由具备权限的账号采集。
-- A/B 的 SPID 以 session.sql 输出为准；输出包含本库实验键锁及持有者/等待者。
SELECT r.session_id,r.blocking_session_id,r.wait_type,r.wait_resource,r.wait_time
FROM sys.dm_exec_requests r WHERE r.database_id=DB_ID() AND r.blocking_session_id>0;
SELECT l.request_session_id,l.resource_type,l.resource_description,l.request_mode,l.request_status,
 OBJECT_SCHEMA_NAME(p.object_id,DB_ID()) schema_name,OBJECT_NAME(p.object_id,DB_ID()) table_name,
 i.name index_name
FROM sys.dm_tran_locks l
JOIN sys.partitions p ON p.hobt_id=l.resource_associated_entity_id
JOIN sys.indexes i ON i.object_id=p.object_id AND i.index_id=p.index_id
WHERE l.resource_database_id=DB_ID() AND OBJECT_SCHEMA_NAME(p.object_id,DB_ID())='w13lab'
ORDER BY l.request_session_id,l.resource_type,l.request_status;
