-- =============================================================================
-- SP Deep Diagnostics — Extended Events Sessions
-- =============================================================================
-- This script creates two XEvent sessions for the SP Deep Diagnostics solution:
--   1. DT_SP_Diagnostics    — Always-on (Layer 2), low overhead, 24/7
--   2. DT_SP_DeepCapture    — On-demand (Layer 3), medium overhead, incident-only
--
-- Prerequisites:
--   - SQL Server 2016+ (2019+ for query_post_execution_plan_profile)
--   - ALTER ANY EVENT SESSION permission
--   - VIEW SERVER STATE permission
--
-- Run this script once on each monitored SQL Server instance.
-- =============================================================================


-- =============================================================================
-- SESSION 1: DT_SP_Diagnostics (Always-On, Layer 2)
-- =============================================================================
-- Captures event-driven data that DMV polling would miss:
--   - Blocking chains (fires when blocking exceeds threshold)
--   - Deadlock graphs (full XML with both queries and lock resources)
--   - Auto-growth events (file growth with duration — key latch trigger)
--   - Sort/hash spill warnings (TempDB spills from insufficient memory grants)
--   - Missing column statistics (optimizer couldn't find stats)
--   - Statement recompilation (why and how often SPs recompile)
--   - Slow statement completion (statements > 5 seconds inside SPs)
-- =============================================================================

-- Drop existing session if present (for re-deployment)
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'DT_SP_Diagnostics')
BEGIN
    ALTER EVENT SESSION [DT_SP_Diagnostics] ON SERVER STATE = STOP;
    DROP EVENT SESSION [DT_SP_Diagnostics] ON SERVER;
END
GO

CREATE EVENT SESSION [DT_SP_Diagnostics] ON SERVER

-- 1. Blocking chains: fires when a session is blocked longer than the
--    'blocked process threshold' (configured below). Captures both the
--    blocker and blocked session details including SQL text.
ADD EVENT sqlserver.blocked_process_report(
    ACTION(
        sqlserver.sql_text,
        sqlserver.session_id,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.client_hostname,
        sqlserver.client_app_name
    )
),

-- 2. Deadlock graphs: captures the full deadlock XML report including
--    both participating queries and their lock resources. Essential for
--    identifying deadlock patterns involving stored procedures.
ADD EVENT sqlserver.xml_deadlock_report(
    ACTION(
        sqlserver.database_name
    )
),

-- 3. Auto-growth events: file growth events with duration. Auto-growth
--    stalls all operations and is a key trigger for latch contention spikes.
ADD EVENT sqlserver.database_file_size_change(
    ACTION(
        sqlserver.database_name,
        sqlserver.sql_text,
        sqlserver.session_id
    )
),

-- 4. Sort spill warnings: fires when a sort operation spills to TempDB
--    because the memory grant was insufficient. Indicates the optimizer
--    underestimated cardinality or the server is under memory pressure.
ADD EVENT sqlserver.sort_warning(
    ACTION(
        sqlserver.sql_text,
        sqlserver.session_id,
        sqlserver.database_name,
        sqlserver.plan_handle
    )
),

-- 5. Hash spill warnings: fires when a hash join/aggregate spills to
--    TempDB. Same root cause as sort warnings — insufficient memory grant.
ADD EVENT sqlserver.hash_warning(
    ACTION(
        sqlserver.sql_text,
        sqlserver.session_id,
        sqlserver.database_name,
        sqlserver.plan_handle
    )
),

-- 6. Missing column statistics: fires when the optimizer cannot find
--    statistics for a column used in a predicate. Leads to bad cardinality
--    estimates and suboptimal execution plans.
ADD EVENT sqlserver.missing_column_statistics(
    ACTION(
        sqlserver.sql_text,
        sqlserver.session_id,
        sqlserver.database_name
    )
),

-- 7. Statement recompilation: fires when a statement inside a stored
--    procedure is recompiled. Frequent recompilation burns CPU and can
--    cause plan instability. The recompile_cause field identifies why.
ADD EVENT sqlserver.sql_statement_recompile(
    ACTION(
        sqlserver.sql_text,
        sqlserver.session_id,
        sqlserver.database_name
    )
    WHERE (
        recompile_cause > 0  -- Filter out trivial recompiles
    )
),

-- 8. Slow statement completion: captures statements inside stored
--    procedures that exceed 5 seconds. Provides duration, CPU time,
--    logical/physical reads, and row counts for root cause analysis.
ADD EVENT sqlserver.sql_statement_completed(
    ACTION(
        sqlserver.sql_text,
        sqlserver.session_id,
        sqlserver.database_name,
        sqlserver.query_hash,
        sqlserver.query_plan_hash
    )
    WHERE (
        duration > 5000000  -- > 5 seconds (duration is in microseconds)
        AND object_type = 8272  -- 8272 = stored procedure
    )
)

-- File target for persistence. Files are written to the SQL Server's
-- default LOG directory. Use sys.fn_xe_file_target_read_file to query.
ADD TARGET package0.event_file(
    SET filename = N'DT_SP_Diagnostics',
        max_file_size = 100,       -- 100 MB per file
        max_rollover_files = 5     -- 500 MB total max
)
WITH (
    MAX_MEMORY = 8192 KB,
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY = 30 SECONDS,
    STARTUP_STATE = ON             -- Survives SQL Server restart
);
GO


-- =============================================================================
-- REQUIRED: Enable blocked process threshold for blocked_process_report
-- =============================================================================
-- The blocked_process_report XEvent only fires when a session has been
-- blocked for longer than this threshold (in seconds). Default is 0 (disabled).
-- Recommended: 5 seconds for production, 2 seconds for development.
-- =============================================================================

EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'blocked process threshold (s)', 5;
RECONFIGURE;
GO


-- =============================================================================
-- Start the always-on session
-- =============================================================================
ALTER EVENT SESSION [DT_SP_Diagnostics] ON SERVER STATE = START;
GO

PRINT 'DT_SP_Diagnostics session created and started successfully.';
GO


-- =============================================================================
-- SESSION 2: DT_SP_DeepCapture (On-Demand, Layer 3 — Pre-2019 Fallback)
-- =============================================================================
-- This session is created but NOT started. It is activated by a Dynatrace
-- Workflow only during active incidents when Davis detects SP degradation.
--
-- VERSION-AWARE LAYER 3 STRATEGY:
--   - SQL Server 2019+: Layer 3 uses sys.dm_exec_query_plan_stats DMV instead.
--     This session is NOT started for SQL 2019+. Zero overhead, no ALTER needed.
--   - SQL Server 2016 SP1 / 2017: Uses lightweight query_thread_profile (~2%).
--     This session IS started as a fallback.
--   - SQL Server pre-2016: Uses standard XEvent with tight time bound (higher
--     risk — document clearly). This session IS started as a fallback.
--
-- It captures heavier, more detailed data:
--   - Per-latch detail with blocking information (latch_suspend_end)
--   - Actual execution plans for slow queries (2019+ only)
--
-- The Workflow starts this session, waits 15 minutes, reads the data, then
-- stops the session to minimize overhead.
-- =============================================================================

-- Drop existing session if present (for re-deployment)
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'DT_SP_DeepCapture')
BEGIN
    ALTER EVENT SESSION [DT_SP_DeepCapture] ON SERVER STATE = STOP;
    DROP EVENT SESSION [DT_SP_DeepCapture] ON SERVER;
END
GO

CREATE EVENT SESSION [DT_SP_DeepCapture] ON SERVER

-- 1. Per-latch detail with blocking information: captures individual latch
--    suspend events > 1ms with the specific latch class, blocking info, and
--    the SQL text that triggered the latch wait. Key latch classes monitored:
--    BUFFER (hot page), FGCB_ADD_REMOVE (TempDB allocation), LOG_MANAGER,
--    ACCESS_METHODS_* (B-tree traversal).
ADD EVENT sqlos.latch_suspend_end(
    SET collect_blocking_information = 1
    ACTION(
        sqlserver.sql_text,
        sqlserver.session_id,
        sqlserver.database_name,
        sqlserver.query_hash,
        sqlserver.plan_handle
    )
    WHERE (
        duration > 1000  -- > 1ms (in microseconds)
        AND (
            latch_class = 'BUFFER'
            OR latch_class = 'ACCESS_METHODS_DATASET_PARENT'
            OR latch_class = 'ACCESS_METHODS_HOBT_VIRTUAL_ROOT'
            OR latch_class = 'FGCB_ADD_REMOVE'
            OR latch_class = 'LOG_MANAGER'
            OR latch_class = 'DBCC_MULTIOBJECT_SCANNER'
            OR latch_class = 'NESTING_TRANSACTION_FULL'
        )
    )
),

-- 2. Actual execution plans for slow queries: lightweight profiling captures
--    the actual execution plan (with runtime stats) for queries exceeding
--    3 seconds. SQL Server 2019+ only.
ADD EVENT sqlserver.query_post_execution_plan_profile(
    ACTION(
        sqlserver.sql_text,
        sqlserver.session_id,
        sqlserver.database_name,
        sqlserver.query_hash
    )
    WHERE (
        duration > 3000000  -- > 3 seconds (in microseconds)
    )
)

-- File target for persistence
ADD TARGET package0.event_file(
    SET filename = N'DT_SP_DeepCapture',
        max_file_size = 200,       -- 200 MB per file
        max_rollover_files = 2     -- 400 MB total max
)
WITH (
    MAX_MEMORY = 16384 KB,
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY = 10 SECONDS,
    STARTUP_STATE = OFF            -- OFF by default — started by Workflow only
);
GO

PRINT 'DT_SP_DeepCapture session created (stopped). Start via Workflow during incidents.';
GO


-- =============================================================================
-- Verification Queries
-- =============================================================================

-- Check session status
SELECT
    s.name AS session_name,
    s.startup_state,
    CASE WHEN r.event_session_id IS NOT NULL THEN 'RUNNING' ELSE 'STOPPED' END AS current_state
FROM sys.server_event_sessions s
LEFT JOIN sys.dm_xe_sessions r ON s.name = r.name
WHERE s.name IN ('DT_SP_Diagnostics', 'DT_SP_DeepCapture');
GO

-- Check blocked process threshold
SELECT name, CAST(value_in_use AS INT) AS value_in_use
FROM sys.configurations
WHERE name = 'blocked process threshold (s)';
GO
