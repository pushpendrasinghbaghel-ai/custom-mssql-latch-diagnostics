# SP Deep Diagnostics — Comprehensive Stored Procedure Root Cause Analysis

> **Extension name:** `custom:mssql.sp.diagnostics`  
> **Version:** 2.0.0  
> **Framework:** EF2 (Extension Framework 2.0) — `sqlMssql` data source  
> **Runs on:** ActiveGate (remote monitoring)

---

## Overview

This solution provides automated root cause analysis for stored procedure performance issues in Microsoft SQL Server. When Davis detects an SP degradation, the system automatically investigates 30+ potential root causes across 5 categories and delivers a plain-English root cause narrative with actionable recommendations — directly on the Problem card.

**It does NOT duplicate** any DMV, metric, or feature set already covered by the official `com.dynatrace.extension.sql-server` extension.

---

## Architecture: 5 Layers

```
┌─────────────────────────────────────────────────────────────┐
│                  SP DEEP DIAGNOSTICS                        │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ LAYER 5: AUTOMATED RCA NARRATION                    │    │
│  │ Davis CoPilot reasons over evidence from all layers  │    │
│  │ Posts root cause + recommendations to Problem card   │    │
│  └──────────────────────┬──────────────────────────────┘    │
│                         │ consumes all layers               │
│  ┌──────────┬───────────┴────┬──────────────┐               │
│  │          │                │              │               │
│  ▼          ▼                ▼              ▼               │
│ LAYER 1   LAYER 2        LAYER 3       LAYER 4             │
│ Always-On  Always-On      On-Demand     Periodic            │
│ Metrics    Events         Deep Capture  Health Check         │
│ (EF2 Ext)  (XEvents)     (Workflow)    (EF2/hourly)         │
│                                                             │
│ Overhead:   Overhead:     Overhead:     Overhead:            │
│ Low         Low           Medium        Low                  │
│ Runs: 24/7  Runs: 24/7   Runs: During  Runs: Hourly         │
│                           incidents                          │
│                           only                               │
└─────────────────────────────────────────────────────────────┘
```

| Layer | Component | Purpose |
|-------|-----------|---------|
| **1** | EF2 Extension (this repo) | Always-on DMV metrics: latch stats, wait analysis, memory grants, TempDB usage, I/O latency, index operational stats, proc wait breakdown, plan regression, blocking chains |
| **2** | XEvent Sessions (`xevent_sessions.sql`) | Event-driven capture: blocked process reports, deadlock graphs, auto-growth events, sort/hash spill warnings, missing statistics, recompilation, slow statement completion |
| **3** | Deep Capture (workflow-triggered) | On-demand `DT_SP_DeepCapture` XEvent session activated only during incidents for per-latch detail and actual execution plans |
| **4** | Health Check (EF2 Extension, hourly) | Periodic structural checks: missing indexes, index fragmentation, stale statistics, server configuration compliance |
| **5** | Davis CoPilot RCA (`workflow_rca.json`) | Automated root cause analysis: gathers evidence from all layers, feeds to CoPilot with decision tree, posts narrative to Problem card |

---

## Root Cause Categories Covered

| # | Category | Issues Detected |
|---|----------|----------------|
| 1 | **Query Execution** | Parameter sniffing, plan regression, stale statistics, implicit conversions, excessive recompilation |
| 2 | **Contention** | Lock blocking, latch contention, deadlocks, spinlock contention, TempDB contention |
| 3 | **Resource Pressure** | Memory grant starvation, TempDB spills, I/O bottleneck, CPU saturation, log file bottleneck, auto-growth stalls |
| 4 | **Schema/Design** | Missing indexes, index fragmentation, oversized temp tables |
| 5 | **Configuration** | MAXDOP misconfiguration, cost threshold too low, max memory misconfigured, TempDB files misconfigured |

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Dynatrace** | Version ≥ 1.303 |
| **ActiveGate** | Environment or cluster ActiveGate with Remote Monitoring module enabled |
| **SQL Server** | 2016+ (2017+ required for Query Store Wait Stats — feature sets `proc_wait_breakdown`, `plan_regression_detection`) |
| **SQL Permissions** | `VIEW SERVER STATE` + `VIEW DATABASE STATE` (see `permissions.sql`) |
| **Query Store** | Must be enabled on each database for `proc_wait_breakdown` and `plan_regression_detection` |
| **Default Trace** | Must be running (enabled by default) for `autogrowth_events` |
| **system_health XE** | Must be running (enabled by default) for `deadlock_graphs` |

---

## Repository Structure

```
custom-mssql-latch-diagnostics/
├── extension/
│   └── extension.yaml          # EF2 extension definition (15 feature sets)
├── dashboard.json              # Dynatrace dashboard (6 sections)
├── workflow_rca.json           # RCA workflow with Davis CoPilot integration
├── xevent_sessions.sql         # XEvent session deployment script (Layer 2 & 3)
├── permissions.sql             # Minimum SQL Server permissions script
├── sample_dql_queries.md       # 16 ready-to-use DQL queries for Notebooks
└── README.md                   # This file
```

---

## Installation

### Step 1: Configure SQL Server Permissions

Run `permissions.sql` on each monitored SQL Server instance. Replace `<strong_password>` and `YourDatabase` with actual values.

```sql
-- Run on the target SQL Server
-- See permissions.sql for the full script
CREATE LOGIN [dynatrace_monitor] WITH PASSWORD = '<strong_password>';
GRANT VIEW SERVER STATE TO [dynatrace_monitor];

USE [YourDatabase];
CREATE USER [dynatrace_monitor] FOR LOGIN [dynatrace_monitor];
GRANT VIEW DATABASE STATE TO [dynatrace_monitor];
```

### Step 2: Deploy XEvent Sessions (Layer 2 & 3)

Run `xevent_sessions.sql` on each monitored SQL Server instance. This creates:
- `DT_SP_Diagnostics` — always-on session (starts automatically)
- `DT_SP_DeepCapture` — on-demand session (stays stopped until Workflow triggers it)

```sql
-- Run the full xevent_sessions.sql script
-- Verify sessions are created:
SELECT name, startup_state FROM sys.server_event_sessions
WHERE name IN ('DT_SP_Diagnostics', 'DT_SP_DeepCapture');
```

### Step 3: Package and Upload the Extension

```powershell
# From the project root:
Compress-Archive -Path extension -DestinationPath custom_mssql.sp.diagnostics-2.0.0.zip
```

Or using `dt-cli`:

```bash
dt extension assemble --source extension --output custom_mssql.sp.diagnostics-2.0.0.zip
```

Upload via **Dynatrace Hub → Upload custom extension** or the API:

```
POST /api/v2/extensions
Content-Type: application/octet-stream
Body: <ZIP file>
```

### Step 4: Configure Monitoring

1. Go to **Settings → Monitoring → Monitored technologies → Custom extensions**
2. Find `custom:mssql.sp.diagnostics`
3. Add a monitoring configuration:
   - Specify the ActiveGate group
   - Enter SQL Server connection details (host, port, authentication)
   - Select the target database (important for Query Store features)
4. Enable the feature sets you need (see below)

### Step 5: Import Dashboard

Import `dashboard.json` via **Dashboards → Import dashboard** or the API:

```
POST /api/config/v1/dashboards
Content-Type: application/json
Body: <dashboard.json contents>
```

### Step 6: Import RCA Workflow

Import `workflow_rca.json` via **Workflows → Upload** or the API. Configure:
- Adjust the trigger filter to match your database service entity tags
- Test with a synthetic problem to verify the flow

---

## Feature Sets

Each feature set can be independently enabled or disabled. Start with the sets most relevant to your issue.

### Layer 1 — Always-On Metrics (Low Overhead)

| Feature Set | Description | Interval | SQL Server | DMV Source |
|---|---|---|---|---|
| `latch_analysis` | Latch wait time/count/max by latch class | 1 min | 2016+ | `sys.dm_os_latch_stats` |
| `wait_analysis` | OS wait stats for latch, I/O, memory, CPU, lock wait types | 1 min | 2016+ | `sys.dm_os_wait_stats` |
| `memory_grants` | Memory grant pressure: waiting count, deficit, per-session detail | 1 min | 2016+ | `sys.dm_exec_query_memory_grants` |
| `tempdb_usage` | TempDB usage: total and top session consumption | 1 min | 2016+ | `sys.dm_db_task_space_usage` |
| `file_io_detail` | Per-file I/O latency: read/write latency, stall time | 1 min | 2016+ | `sys.dm_io_virtual_file_stats` |
| `index_operational_stats` | Per-index page latch/IO latch/row lock/page lock contention | 5 min | 2016+ | `sys.dm_db_index_operational_stats` |
| `proc_wait_breakdown` | Per-statement wait analysis inside SPs from Query Store | 5 min | **2017+** | `sys.query_store_wait_stats` |
| `plan_regression_detection` | Multi-plan queries with high variance ratio (parameter sniffing) | 5 min | **2017+** | `sys.query_store_plan` |
| `blocking_chains` | Active blocking chains with blocker/blocked query text | 1 min | 2016+ | `sys.dm_exec_requests` |
| `autogrowth_events` | Data/log file auto-grow/shrink events from default trace | 5 min | 2016+ | `sys.fn_trace_gettable` |
| `deadlock_graphs` | Deadlock XML graphs from system_health XE ring buffer | 5 min | 2016+ | `sys.dm_xe_session_targets` |

### Layer 4 — Periodic Health Check (Low Overhead)

| Feature Set | Description | Interval | SQL Server | DMV Source |
|---|---|---|---|---|
| `missing_indexes` | Top 25 missing indexes by improvement score | 1 hour | 2016+ | `sys.dm_db_missing_index_details` |
| `index_fragmentation` | Indexes with > 10% fragmentation and > 1000 pages (LIMITED mode) | 1 hour | 2016+ | `sys.dm_db_index_physical_stats` |
| `stale_statistics` | Statistics with high modification count relative to row count | 1 hour | 2016+ | `sys.dm_db_stats_properties` |
| `server_config_check` | Key server configs (MAXDOP, cost threshold, memory, TempDB files) | 1 hour | 2016+ | `sys.configurations` |

### Recommended Starting Configurations

| Scenario | Enable These Feature Sets |
|---|---|
| **Latch investigation** | `latch_analysis` + `wait_analysis` + `autogrowth_events` + `index_operational_stats` |
| **Blocking investigation** | `blocking_chains` + `wait_analysis` + `deadlock_graphs` |
| **SP performance triage** | `proc_wait_breakdown` + `plan_regression_detection` + `memory_grants` + `tempdb_usage` |
| **Full RCA (all layers)** | All feature sets enabled |

---

## DDU Consumption Estimates

| Feature Set | Metrics/Poll | Dimensions | Est. DDU/Hour |
|---|---|---|---|
| `latch_analysis` | 3 × ~20 rows | 2 | ~0.04 |
| `wait_analysis` | 4 × ~20 rows | 2 | ~0.05 |
| `memory_grants` | 3 aggregate + 4 × 20 detail | 3 | ~0.06 |
| `tempdb_usage` | 2 aggregate | 1 | ~0.01 |
| `file_io_detail` | 5 × ~15 rows | 4 | ~0.05 |
| `index_operational_stats` | 10 × ~50 rows (5 min) | 5 | ~0.10 |
| `proc_wait_breakdown` | 10 × ~100 rows (5 min) | 6 | ~0.15 |
| `plan_regression_detection` | 5 × ~10 rows + 1 agg (5 min) | 4 | ~0.03 |
| `blocking_chains` | 1 × variable + 1 agg | 11 | ~0.03 |
| `autogrowth_events` | 3 × variable (5 min) | 4 | ~0.01 |
| `deadlock_graphs` | 1 × variable (5 min) | 3 | ~0.01 |
| `missing_indexes` | 3 × 25 rows (hourly) | 6 | ~0.01 |
| `index_fragmentation` | 2 × variable (hourly) | 5 | ~0.01 |
| `stale_statistics` | 3 × variable (hourly) | 5 | ~0.01 |
| `server_config_check` | 1 × 7 + 2 (hourly) | 2 | ~0.01 |
| **Total (all enabled)** | | | **~0.58/hr ≈ 14 DDU/day** |

*Estimates assume a moderately active SQL Server with typical cardinality. Actual consumption varies based on the number of active latch classes, wait types, indexes, and blocking chains.*

---

## Troubleshooting

### Extension not collecting data
1. Verify ActiveGate connectivity to SQL Server (port 1433)
2. Check SQL permissions: `SELECT HAS_PERMS_BY_NAME(null, null, 'VIEW SERVER STATE')`
3. Review ActiveGate logs: `remotepluginmodule.log`

### `proc_wait_breakdown` returns no data
- Verify Query Store is enabled: `SELECT actual_state_desc FROM sys.database_query_store_options`
- Verify SQL Server is 2017+: `SELECT @@VERSION`
- Ensure the extension is configured against the correct database

### `autogrowth_events` returns no data
- Verify default trace is running: `SELECT * FROM sys.traces WHERE id = 1`
- Check time window: events only show up if auto-growth occurred in last 10 minutes

### `deadlock_graphs` returns no data
- Verify system_health XE is running: `SELECT * FROM sys.dm_xe_sessions WHERE name = 'system_health'`
- Deadlocks must have occurred in the last 10 minutes to appear

### XEvent sessions not capturing data
- Verify session is running: `SELECT * FROM sys.dm_xe_sessions WHERE name = 'DT_SP_Diagnostics'`
- Check blocked process threshold: `SELECT value_in_use FROM sys.configurations WHERE name = 'blocked process threshold (s)'` (must be > 0)

### High DDU consumption
- Disable feature sets you don't need
- `index_operational_stats` and `proc_wait_breakdown` generate the most data — consider disabling if not actively investigating

---

## Known Limitations

1. **Database-scoped queries:** Feature sets `proc_wait_breakdown`, `plan_regression_detection`, `missing_indexes`, `index_fragmentation`, and `stale_statistics` operate on the database specified in the monitoring configuration. To monitor multiple databases, create separate monitoring configurations.

2. **Query Store dependency:** Feature sets 7 (`proc_wait_breakdown`) and 8 (`plan_regression_detection`) require SQL Server 2017+ with Query Store enabled. They will return empty results on SQL Server 2016 or if Query Store is disabled.

3. **Cumulative DMV counters:** `sys.dm_os_latch_stats` and `sys.dm_os_wait_stats` return cumulative values since SQL Server startup. To see delta/rate, use the `rate` function in DQL or examine trends over time.

4. **Dimension cardinality:** High-cardinality dimensions (like `query_sql_text`, `deadlock_graph`) may increase DDU consumption. The queries use `TOP N` limits to constrain result sets.

5. **Deep Capture (Layer 3):** The `DT_SP_DeepCapture` XEvent session requires `ALTER ANY EVENT SESSION` permission to start/stop via Workflow. If this permission isn't granted, the session must be managed manually by a DBA.

6. **Index fragmentation overhead:** The `index_fragmentation` feature set uses `LIMITED` mode to minimize impact, but can still be resource-intensive on very large databases. It runs hourly by default.

7. **XEvent file target location:** The `DT_SP_Diagnostics` and `DT_SP_DeepCapture` XEvent sessions write .xel files to the SQL Server's default LOG directory. Ensure sufficient disk space (max 500 MB for Layer 2, 400 MB for Layer 3).
