-- Run only on a new Web database that has not installed week10.
-- sqlcmd -b disconnects on the intentional error and rolls back the outer transaction.
:on error exit
USE [$(DatabaseName)];
GO
BEGIN TRANSACTION;
GO
:r sql/week10/install.sql
THROW 56998,'Expected installation fault: roll back the outer migration transaction',1;
GO
