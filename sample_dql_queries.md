# Sample DQL Queries — SP Deep Diagnostics

Use these queries in **Dynatrace Notebooks** or **Dashboards** to analyze the data
captured by `custom:mssql.sp.diagnostics`.

---

## 1. Latch Class Trending — Last Hour

Show which latch classes have the highest cumulative wait time over the past hour.

```dql
timeseries latch_wait = avg(custom.mssql.latch.wait_time_ms),
    by: { latch_class },
    from: now() - 1h
| sort arrayAvg(latch_wait) desc
| limit 20
```

**Top 10 latch classes right now (bar chart):**

```dql
timeseries latch_wait = max(custom.mssql.latch.wait_time_ms),
    by: { latch_class },
    from: now() - 5m
| sort arrayMax(latch_wait) desc
| limit 10
```

---

## 2. Active Blocking Chains with Query Text

List every active blocking chain captured in the last 30 minutes, including
the SQL text of both the blocker and the blocked session.

```dql
timeseries wait = max(custom.mssql.blocking.wait_time_ms),
    by: {
        blocked_spid,
        blocker_spid,
        wait_type,
        database_name,
        blocked_query,
        blocker_query,
        blocked_login,
        blocked_hostname,
        blocked_program
    },
    from: now() - 30m
| filter isNotNull(blocked_spid)
| sort arrayMax(wait) desc
```

**Blocking chain count trend:**

```dql
timeseries chains = avg(custom.mssql.blocking.active_chains),
    from: now() - 6h
```

---

## 3. Wait Type Breakdown — In-Memory vs. I/O vs. CPU vs. Lock

Identify the dominant wait categories across latch, I/O, memory, CPU/parallelism,
and lock waits.

```dql
timeseries wait = avg(custom.mssql.wait.wait_time_ms),
    by: { wait_type },
    from: now() - 1h
| sort arrayAvg(wait) desc
```

**Signal wait ratio (CPU scheduling pressure):**

```dql
timeseries total_wait = avg(custom.mssql.wait.wait_time_ms),
    by: { wait_type },
    from: now() - 1h
| join [
    timeseries signal_wait = avg(custom.mssql.wait.signal_wait_time_ms),
        by: { wait_type },
        from: now() - 1h
  ], on: { wait_type }
```

---

## 4. Memory Grant Pressure — Spill Risk Detection

Identify memory grant starvation indicating TempDB spill risk.

```dql
timeseries {
        deficit = avg(custom.mssql.memory.grant_deficit_kb),
        waiting = avg(custom.mssql.memory.grant_waiting_count),
        wait_time = avg(custom.mssql.memory.grant_wait_time_ms)
    },
    from: now() - 6h
```

**Per-session detail — sessions with largest memory grants:**

```dql
timeseries {
        requested = max(custom.mssql.memory.requested_kb),
        granted = max(custom.mssql.memory.granted_kb),
        used = max(custom.mssql.memory.used_kb),
        ideal = max(custom.mssql.memory.ideal_kb)
    },
    by: { session_id, database_name },
    from: now() - 1h
| sort arrayMax(requested) desc
| limit 10
```

---

## 5. TempDB Usage Trend

Monitor overall TempDB usage and identify sessions consuming the most space.

```dql
timeseries {
        total = avg(custom.mssql.tempdb.total_usage_kb),
        top_session = avg(custom.mssql.tempdb.top_session_usage_kb)
    },
    from: now() - 6h
```

---

## 6. Per-Statement Wait Breakdown Inside a Stored Procedure

Find statements inside stored procedures that caused specific wait categories.
Replace `YourProcName` with the actual procedure name.

```dql
timeseries total_wait = max(custom.mssql.proc_wait.total_wait_time_ms),
    by: { proc_name, query_sql_text, wait_category_desc },
    from: now() - 1h
| filter proc_name == "YourProcName"
| sort arrayMax(total_wait) desc
```

**Top 20 statements by total wait time (any procedure):**

```dql
timeseries total_wait = max(custom.mssql.proc_wait.total_wait_time_ms),
    by: { proc_name, query_sql_text, wait_category_desc },
    from: now() - 1h
| sort arrayMax(total_wait) desc
| limit 20
```

**Execution profile for a specific procedure (duration, CPU, IO, memory, TempDB):**

```dql
timeseries {
        avg_dur = avg(custom.mssql.proc_wait.avg_duration),
        avg_cpu = avg(custom.mssql.proc_wait.avg_cpu_time),
        avg_lio = avg(custom.mssql.proc_wait.avg_logical_io_reads),
        avg_pio = avg(custom.mssql.proc_wait.avg_physical_io_reads),
        avg_mem = avg(custom.mssql.proc_wait.avg_query_max_used_memory),
        avg_tdb = avg(custom.mssql.proc_wait.avg_tempdb_space_used),
        execs   = avg(custom.mssql.proc_wait.count_executions)
    },
    by: { proc_name, query_sql_text },
    from: now() - 1h
| filter proc_name == "YourProcName"
```

---

## 7. Plan Regression Detection — Multi-Plan Queries

Find queries inside stored procedures that have multiple execution plans with
significantly different performance (parameter sniffing fingerprint).

```dql
timeseries {
        variance = max(custom.mssql.plan.variance_ratio),
        plans = max(custom.mssql.plan.plan_count),
        best = min(custom.mssql.plan.best_avg_duration),
        worst = max(custom.mssql.plan.worst_avg_duration)
    },
    by: { proc_name, query_sql_text, query_id },
    from: now() - 1h
| sort arrayMax(variance) desc
| limit 10
```

**Multi-plan query count trend:**

```dql
timeseries count = avg(custom.mssql.plan.multi_plan_query_count),
    from: now() - 24h
```

---

## 8. I/O Latency per File with Threshold Flagging

Identify database files with read latency > 20ms or write latency > 5ms.

```dql
timeseries {
        read_lat = avg(custom.mssql.io.read_latency_ms),
        write_lat = avg(custom.mssql.io.write_latency_ms)
    },
    by: { database_name, file_name, file_type },
    from: now() - 1h
| sort arrayAvg(read_lat) desc
```

**Flag problematic files (read > 20ms or write > 5ms on log files):**

```dql
timeseries {
        read_lat = avg(custom.mssql.io.read_latency_ms),
        write_lat = avg(custom.mssql.io.write_latency_ms)
    },
    by: { database_name, file_name, file_type },
    from: now() - 1h
| filter arrayAvg(read_lat) > 20 OR (file_type == "LOG" AND arrayAvg(write_lat) > 5)
```

---

## 9. Index Lock & Latch Contention — Hot Indexes

Find specific indexes with the highest page latch or lock contention.

```dql
timeseries latch = max(custom.mssql.index.page_latch_wait_ms),
    by: { database_name, table_name, index_name, index_type },
    from: now() - 1h
| sort arrayMax(latch) desc
| limit 15
```

**Full index contention profile:**

```dql
timeseries {
        pg_latch = max(custom.mssql.index.page_latch_wait_ms),
        pg_io = max(custom.mssql.index.page_io_latch_wait_ms),
        row_lock = max(custom.mssql.index.row_lock_wait_ms),
        pg_lock = max(custom.mssql.index.page_lock_wait_ms),
        scans = max(custom.mssql.index.range_scan_count),
        lookups = max(custom.mssql.index.singleton_lookup_count)
    },
    by: { table_name, index_name },
    from: now() - 1h
| sort arrayMax(pg_latch) desc
| limit 10
```

---

## 10. Auto-Growth Timeline Overlaid with Latch Spikes

Correlate auto-growth events with latch wait time to identify if file growth
triggered latch contention.

```dql
timeseries {
        latch_wait   = avg(custom.mssql.latch.wait_time_ms),
        growth_count = sum(custom.mssql.autogrowth.event_count)
    },
    from: now() - 6h
```

**Growth event details with duration:**

```dql
timeseries {
        duration = max(custom.mssql.autogrowth.duration_us),
        pages    = max(custom.mssql.autogrowth.growth_pages)
    },
    by: { event_name, database_name, file_name },
    from: now() - 6h
| filter arrayMax(pages) > 0
```

---

## 11. Missing Index Recommendations Sorted by Improvement Score

Show the highest-impact missing indexes identified by the optimizer.

```dql
timeseries score = max(custom.mssql.missing_index.improvement_score),
    by: { table_name, equality_columns, inequality_columns, included_columns },
    from: now() - 2h
| sort arrayMax(score) desc
| limit 25
```

---

## 12. Index Fragmentation — Rebuild Candidates

List indexes with fragmentation above 30% (rebuild threshold).

```dql
timeseries frag = max(custom.mssql.fragmentation.avg_percent),
    by: { database_name, table_name, index_name, index_type },
    from: now() - 2h
| filter arrayMax(frag) > 30
| sort arrayMax(frag) desc
```

---

## 13. Stale Statistics — Auto-Stats Not Keeping Up

Find tables where statistics modification percentage exceeds 20%.

```dql
timeseries mod_pct = max(custom.mssql.stats.modification_percent),
    by: { table_name, stats_name, stats_last_updated },
    from: now() - 2h
| filter arrayMax(mod_pct) > 20
| sort arrayMax(mod_pct) desc
```

---

## 14. Server Configuration Compliance Check

Flag known misconfigurations that contribute to performance issues.

```dql
timeseries val = avg(custom.mssql.config.value),
    by: { config_name },
    from: now() - 2h
```

**TempDB file configuration check:**

```dql
timeseries {
        file_count = avg(custom.mssql.config.tempdb_file_count),
        files_equal = avg(custom.mssql.config.tempdb_files_equal)
    },
    from: now() - 2h
```

---

## 15. Deadlock Events — Last 24h

```dql
timeseries deadlocks = sum(custom.mssql.deadlock.event_count),
    by: { deadlock_time, deadlock_graph },
    from: now() - 24h
| filter arraySum(deadlocks) > 0
| sort deadlock_time desc
```

**Deadlock count trend:**

```dql
timeseries deadlocks = sum(custom.mssql.deadlock.event_count),
    from: now() - 7d
```

---

## 16. Correlation: Blocking vs. Latch Wait Time

```dql
timeseries {
        latch_wait = avg(custom.mssql.latch.wait_time_ms),
        chains     = avg(custom.mssql.blocking.active_chains)
    },
    from: now() - 6h
```
