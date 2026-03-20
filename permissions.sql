-- =============================================================================
-- SP Deep Diagnostics — Minimum Required Permissions
-- =============================================================================
-- This script creates and configures the monitoring user with the minimum
-- permissions required for the SP Deep Diagnostics solution.
--
-- Run this script on each monitored SQL Server instance.
-- Replace '<strong_password>' with a secure password.
-- Replace 'YourDatabase' with each database you want to monitor.
-- =============================================================================


-- =============================================================================
-- 1. Create the monitoring login and base permissions
-- =============================================================================
-- VIEW SERVER STATE: Required for all server-level DMVs
--   - sys.dm_os_latch_stats
--   - sys.dm_os_wait_stats
--   - sys.dm_exec_query_memory_grants
--   - sys.dm_exec_requests / sys.dm_exec_sessions
--   - sys.dm_io_virtual_file_stats
--   - sys.dm_db_task_space_usage
--   - sys.dm_db_index_operational_stats
--   - sys.dm_xe_session_targets / sys.dm_xe_sessions
--   - sys.configurations
--   - sys.master_files
--   - sys.traces / sys.fn_trace_gettable

USE [master];
GO

-- Create login (skip if already exists)
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'dynatrace_monitor')
BEGIN
    CREATE LOGIN [dynatrace_monitor] WITH PASSWORD = '<strong_password>',
        DEFAULT_DATABASE = [master],
        CHECK_EXPIRATION = OFF,
        CHECK_POLICY = ON;
END
GO

-- Grant server-level VIEW SERVER STATE
GRANT VIEW SERVER STATE TO [dynatrace_monitor];
GO


-- =============================================================================
-- 2. Database-level permissions (repeat for each monitored database)
-- =============================================================================
-- VIEW DATABASE STATE: Required for Query Store views (Feature Sets 7, 8)
--   - sys.query_store_wait_stats
--   - sys.query_store_runtime_stats
--   - sys.query_store_plan
--   - sys.query_store_query
--   - sys.query_store_query_text
--
-- Also required for:
--   - sys.dm_db_missing_index_details (Feature Set 9)
--   - sys.dm_db_index_physical_stats (Feature Set 10)
--   - sys.dm_db_stats_properties (Feature Set 11)
--   - sys.stats (Feature Set 11)
--   - sys.indexes (Feature Sets 5, 10)

-- >>> Replace 'YourDatabase' with your actual database name <<<
USE [YourDatabase];
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'dynatrace_monitor')
BEGIN
    CREATE USER [dynatrace_monitor] FOR LOGIN [dynatrace_monitor];
END
GO

GRANT VIEW DATABASE STATE TO [dynatrace_monitor];
GO


-- =============================================================================
-- 3. XEvent session management permissions (Layer 2 & 3)
-- =============================================================================
-- ALTER ANY EVENT SESSION: Required to create, start, and stop the
-- DT_SP_Diagnostics (Layer 2) and DT_SP_DeepCapture (Layer 3) sessions.
--
-- NOTE: This is a server-level permission. If you prefer not to grant this
-- to the monitoring user, deploy the XEvent sessions manually using
-- xevent_sessions.sql with a DBA account.

USE [master];
GO

-- Option A: Grant to the monitoring user (allows Workflow-triggered deep capture)
GRANT ALTER ANY EVENT SESSION TO [dynatrace_monitor];
GO

-- Option B (alternative): If you don't want the monitoring user to manage
-- XEvent sessions, skip the GRANT above and deploy sessions manually.
-- The Layer 3 deep capture Workflow will not be able to start/stop sessions
-- automatically — a DBA will need to do it manually during incidents.


-- =============================================================================
-- 4. Verification
-- =============================================================================
-- Run these queries to verify the permissions are correctly configured.

-- Check server-level permissions
SELECT
    perm.permission_name,
    perm.state_desc
FROM sys.server_permissions perm
INNER JOIN sys.server_principals sp ON perm.grantee_principal_id = sp.principal_id
WHERE sp.name = 'dynatrace_monitor';
GO

-- Check database-level permissions (run in each target database)
-- USE [YourDatabase];
-- SELECT
--     perm.permission_name,
--     perm.state_desc
-- FROM sys.database_permissions perm
-- INNER JOIN sys.database_principals dp ON perm.grantee_principal_id = dp.principal_id
-- WHERE dp.name = 'dynatrace_monitor';
-- GO

PRINT 'Permissions configured successfully for dynatrace_monitor.';
GO
