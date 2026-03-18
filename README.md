# MSSQL Latch & Blocking Deep Diagnostics — Dynatrace Extension 2.0

> **Extension name:** `custom:mssql.latch.diagnostics`
> **Version:** 1.0.0
> **Framework:** EF2 (Extension Framework 2.0) — `sqlMssql` data source
> **Runs on:** ActiveGate (remote monitoring)

---

## Overview

This custom extension fills critical observability gaps left by the official Dynatrace SQL Server extension (`com.dynatrace.extension.sql-server`). It provides deep latch contention analysis, blocking chain diagnostics with full query text, per-statement wait breakdowns inside stored procedures, auto-growth event detection, and deadlock graph capture.

**It does NOT duplicate** any DMV, metric, or feature set already covered by the official extension.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Dynatrace** | Version ≥ 1.303 |
| **ActiveGate** | Environment or cluster ActiveGate with the Remote Monitoring module enabled |
| **SQL Server** | 2016+ (2017+ required for Query Store Wait Stats — feature set `proc_wait_breakdown`) |
| **SQL Permissions** | `VIEW SERVER STATE` (for server-level DMVs) + `VIEW DATABASE STATE` (for Query Store views) |
| **Query Store** | Must be enabled on each database you want `proc_wait_breakdown` data for |
| **Default Trace** | Must be running (enabled by default) for `autogrowth_events` |
| **system_health XE** | Must be running (enabled by default) for `deadlock_graphs` |

### Creating the monitoring user

```sql
-- On the target SQL Server instance:
CREATE LOGIN [dynatrace_monitor] WITH PASSWORD = '<strong_password>';
CREATE USER  [dynatrace_monitor] FOR LOGIN [dynatrace_monitor];

GRANT VIEW SERVER STATE TO [dynatrace_monitor];

-- For each database where you want Query Store data:
USE [YourDatabase];
GRANT VIEW DATABASE STATE TO [dynatrace_monitor];
```

---

## Extension Package Structure

```
custom_mssql.latch.diagnostics-1.0.0.zip
└── extension/
    └── extension.yaml
```

### How to Package

```powershell
# From the project root:
Compress-Archive -Path extension -DestinationPath custom_mssql.latch.diagnostics-1.0.0.zip
```

Or using the Dynatrace Extension CLI (`dt-cli`):

```bash
dt extension assemble --source extension --output custom_mssql.latch.diagnostics-1.0.0.zip
```

### How to Upload and Activate

1. **Upload** — Navigate to **Dynatrace Hub → Upload custom extension** and upload the ZIP file. Alternatively, use the Extensions API v2:
   ```
   POST /api/v2/extensions
   Content-Type: application/octet-stream
   Body: <ZIP file>
   ```

2. **Configure monitoring** — After upload, go to **Settings → Monitoring → Monitored technologies → Custom extensions**, find `custom:mssql.latch.diagnostics`, and add a monitoring configuration:
   - Specify the ActiveGate group
   - Enter SQL Server connection details (host, port, authentication)
   - Select the target database (important for `proc_wait_breakdown`)

3. **Enable feature sets** — In the monitoring configuration, enable or disable individual feature sets based on your needs (see below).

---

## Feature Sets

Each feature set can be independently enabled or disabled. Start with the sets most relevant to your issue and expand from there.

| Feature Set | Description | Polling Interval | SQL Server Version |
|---|---|---|---|
| `latch_analysis` | Latch wait time, request count, and max wait broken down by latch class (e.g., `BUFFER`, `FGCB_ADD_REMOVE`) from `sys.dm_os_latch_stats` | 1 minute | 2016+ |
| `blocking_chains` | Active blocking chains with blocker/blocked session IDs, query text for both sides, wait type, database, login, host, and program | 1 minute | 2016+ |
| `wait_stats` | OS-level wait statistics for latch-related wait types (`PAGELATCH_*`, `PAGEIOLATCH_*`, `LATCH_*`, `IO_COMPLETION`, `WRITELOG`, etc.) from `sys.dm_os_wait_stats` | 1 minute | 2016+ |
| `proc_wait_breakdown` | Per-statement wait analysis inside stored procedures: which statement caused the latch wait, with execution counts, duration, CPU, and IO stats from Query Store | 5 minutes | **2017+** |
| `autogrowth_events` | Data file and log file auto-grow/shrink events captured from the SQL Server default trace | 5 minutes | 2016+ |
| `deadlock_graphs` | Full deadlock XML graphs from the `system_health` Extended Events ring buffer, with timestamp filtering to avoid re-ingestion | 5 minutes | 2016+ |

### Recommended Starting Configuration

- **Latch investigation:** Enable `latch_analysis` + `wait_stats` + `autogrowth_events`
- **Blocking investigation:** Enable `blocking_chains` + `deadlock_graphs`
- **Stored procedure tuning:** Enable `proc_wait_breakdown`
- **Full diagnostics:** Enable all feature sets

---

## Metrics Reference

### Latch Analysis (`latch_analysis`)

| Metric Key | Display Name | Unit | Dimension |
|---|---|---|---|
| `custom.mssql.latch.wait_time_ms` | Latch Wait Time | MilliSecond | `latch_class` |
| `custom.mssql.latch.waiting_requests` | Latch Waiting Requests | Count | `latch_class` |
| `custom.mssql.latch.max_wait_time_ms` | Latch Max Wait Time | MilliSecond | `latch_class` |

### Blocking Chains (`blocking_chains`)

| Metric Key | Display Name | Unit | Dimensions |
|---|---|---|---|
| `custom.mssql.blocking.wait_time_ms` | Blocking Wait Time | MilliSecond | `blocked_spid`, `blocker_spid`, `wait_type`, `wait_resource`, `database_name`, `blocked_query`, `blocker_query`, `blocked_login`, `blocked_hostname`, `blocked_program` |
| `custom.mssql.blocking.active_chains` | Active Blocking Chains | Count | *(none — aggregate count)* |

### Wait Stats (`wait_stats`)

| Metric Key | Display Name | Unit | Dimension |
|---|---|---|---|
| `custom.mssql.wait.wait_time_ms` | OS Wait Time | MilliSecond | `wait_type` |
| `custom.mssql.wait.waiting_tasks` | Waiting Tasks Count | Count | `wait_type` |
| `custom.mssql.wait.max_wait_time_ms` | OS Max Wait Time | MilliSecond | `wait_type` |
| `custom.mssql.wait.signal_wait_time_ms` | Signal Wait Time | MilliSecond | `wait_type` |

### Procedure Wait Breakdown (`proc_wait_breakdown`)

| Metric Key | Display Name | Unit | Dimensions |
|---|---|---|---|
| `custom.mssql.proc_wait.total_wait_time_ms` | Proc Statement Total Wait Time | MilliSecond | `query_sql_text`, `proc_name`, `wait_category_desc` |
| `custom.mssql.proc_wait.avg_wait_time_ms` | Proc Statement Avg Wait Time | MilliSecond | *(same)* |
| `custom.mssql.proc_wait.max_wait_time_ms` | Proc Statement Max Wait Time | MilliSecond | *(same)* |
| `custom.mssql.proc_wait.count_executions` | Proc Statement Execution Count | Count | *(same)* |
| `custom.mssql.proc_wait.avg_duration` | Proc Statement Avg Duration | MicroSecond | *(same)* |
| `custom.mssql.proc_wait.avg_cpu_time` | Proc Statement Avg CPU Time | MicroSecond | *(same)* |
| `custom.mssql.proc_wait.avg_logical_io_reads` | Proc Statement Avg Logical IO Reads | Count | *(same)* |

### Auto-Growth Events (`autogrowth_events`)

| Metric Key | Display Name | Unit | Dimensions |
|---|---|---|---|
| `custom.mssql.autogrowth.duration_us` | Auto-Growth Duration | MicroSecond | `event_name`, `database_name`, `file_name` |
| `custom.mssql.autogrowth.growth_pages` | Auto-Growth Size (Pages) | Count | *(same)* |
| `custom.mssql.autogrowth.event_count` | Auto-Growth Event Count | Count | *(same)* |

### Deadlock Graphs (`deadlock_graphs`)

| Metric Key | Display Name | Unit | Dimensions |
|---|---|---|---|
| `custom.mssql.deadlock.event_count` | Deadlock Event Count | Count | `deadlock_time`, `deadlock_graph` |

---

## DDU Consumption Estimates

Davis Data Units (DDU) consumption depends on metric cardinality. Below are **per-instance, per-hour** estimates.

| Feature Set | Estimated DDUs/hr | Key Cardinality Driver |
|---|---|---|
| `latch_analysis` | 0.1 – 0.5 | Number of distinct `latch_class` values (~30 classes with activity) |
| `blocking_chains` | 0.01 – 2.0 | Number of concurrent blocking chains (often 0; spikes under contention) |
| `wait_stats` | 0.05 – 0.2 | Fixed set of 15 wait types |
| `proc_wait_breakdown` | 0.5 – 3.0 | Number of distinct statements × wait categories (capped at 50 rows) |
| `autogrowth_events` | 0.01 – 0.5 | Number of auto-growth events in the last 10 minutes (often 0) |
| `deadlock_graphs` | 0.01 – 0.2 | Number of deadlocks in the last 10 minutes (capped at 10 rows) |

**Total estimated range:** 0.7 – 6.4 DDUs/hr per monitored instance (with all feature sets enabled).

> **Tip:** Start with `latch_analysis` and `wait_stats` only, then enable additional sets as needed to minimize DDU usage.

---

## Known Limitations

### 1. Auto-Growth Events — Default Trace Alternative

The original design used `xp_readerrorlog` with temporary tables, which EF2's single-statement SQL execution model does not support. This extension uses the **SQL Server default trace** (`sys.fn_trace_gettable`) instead.

- The default trace is a rolling set of files with limited size (~20 MB per file, 5 files).
- If the default trace is disabled (`sp_configure 'default trace enabled'`), this feature set will return no data.
- The 10-minute lookback window may miss events on extremely busy servers where the trace rolls over quickly.

**OneAgent Log Monitoring Alternative:**

If the default trace approach is insufficient, configure OneAgent to ingest the SQL Server error log directly:

1. Find the error log path:
   ```sql
   SELECT SERVERPROPERTY('ErrorLogFileName');
   ```
2. In Dynatrace, go to **Settings → Log Monitoring → Log sources** and add the error log path.
3. Use log processing rules to extract auto-growth events (match `autogrow` in the log text).

### 2. Deadlock Graph Truncation

Deadlock XML graphs from the `system_health` ring buffer can exceed 10 KB. The extension truncates the `deadlock_graph` dimension to 4,000 characters. For full deadlock analysis:

- Use SQL Server Management Studio (SSMS) to view complete deadlock graphs.
- Or configure a dedicated Extended Events session to write deadlock reports to a file target.

### 3. Query Store Availability

The `proc_wait_breakdown` feature set requires:

- SQL Server 2017 or later (for `sys.query_store_wait_stats`).
- Query Store enabled on the target database (`ALTER DATABASE [YourDB] SET QUERY_STORE = ON`).
- The extension must be configured to connect to the database with Query Store enabled.

If Query Store is not enabled, this feature set will produce errors in the extension logs. Disable it in the monitoring configuration if not applicable.

### 4. Ring Buffer Size

The `system_health` Extended Events session has a finite ring buffer. On busy servers, older events are overwritten. The 10-minute timestamp filter mitigates re-ingestion but cannot recover events that were already overwritten before the extension polled.

### 5. Dimension Cardinality

The `blocking_chains` and `proc_wait_breakdown` feature sets capture query text as dimensions. Very long or highly variable query text can increase DDU consumption. The `blocked_query`, `blocker_query`, and `query_sql_text` dimensions may be truncated by the Dynatrace metric dimension length limit.

### 6. Cumulative vs. Delta Values

The `latch_analysis` and `wait_stats` groups query cumulative DMV counters (`sys.dm_os_latch_stats`, `sys.dm_os_wait_stats`). These counters reset on SQL Server restart. The extension ingests gauge values; use DQL `rate()` or delta calculations in dashboards for per-interval analysis.

---

## Topology

This extension creates topology rules that associate all `custom.mssql.*` metrics with `sql:sql_server_instance` entities. The entity ID is derived from `@@SERVERNAME`.

If you also run the official `com.dynatrace.extension.sql-server` extension, the entities created by this custom extension will have **different entity IDs**. To correlate data from both extensions, filter by the `sql_server_instance` dimension in DQL queries.

---

## Troubleshooting

| Symptom | Possible Cause | Resolution |
|---|---|---|
| No data for any feature set | ActiveGate cannot connect to SQL Server | Verify network connectivity, firewall rules, and SQL authentication from the ActiveGate host |
| `latch_analysis` returns empty | No latch contention at poll time | This is expected during low-activity periods |
| `proc_wait_breakdown` errors | Query Store not enabled or SQL Server < 2017 | Enable Query Store or disable this feature set |
| `autogrowth_events` returns empty | Default trace disabled or no growth events | Verify `sp_configure 'default trace enabled'` returns 1 |
| `deadlock_graphs` returns empty | No deadlocks or ring buffer overwritten | Expected if no deadlocks occurred; check system_health session status |
| High DDU consumption | High cardinality in blocking_chains | Limit monitoring to critical instances; disable `blocking_chains` if DDU budget is tight |

---

## License

This extension is provided as-is for custom diagnostic use. It is not an official Dynatrace extension and is not covered by Dynatrace support agreements.
