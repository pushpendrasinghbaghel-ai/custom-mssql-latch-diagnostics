# Sample DQL Queries — MSSQL Latch & Blocking Diagnostics

Use these queries in **Dynatrace Notebooks** or **Dashboards** to analyze the data
captured by `custom:mssql.latch.diagnostics`.

---

## 1. Latch Waits by Class — Last Hour

Show which latch classes have the highest cumulative wait time.

```dql
timeseries latch_wait = avg(custom.mssql.latch.wait_time_ms),
    by: { latch_class },
    from: now() - 1h
| sort arrayAvg(latch_wait) desc
| limit 20
```

**Bar-chart variant — top 10 latch classes right now:**

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

## 3. Wait Type Breakdown — In-Memory vs. I/O Latch Waits

Identify whether latch contention is in the buffer pool (PAGELATCH) or I/O
bound (PAGEIOLATCH).

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

## 4. Per-Statement Wait Breakdown Inside a Stored Procedure

Find statements inside stored procedures that caused latch or lock waits.
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

**Execution profile for a specific statement (duration, CPU, IO):**

```dql
timeseries {
        avg_dur = avg(custom.mssql.proc_wait.avg_duration),
        avg_cpu = avg(custom.mssql.proc_wait.avg_cpu_time),
        avg_io  = avg(custom.mssql.proc_wait.avg_logical_io_reads),
        execs   = avg(custom.mssql.proc_wait.count_executions)
    },
    by: { proc_name, query_sql_text },
    from: now() - 1h
| filter proc_name == "YourProcName"
```

---

## 5. Auto-Growth Event Timeline

Show auto-growth events on a timeline — useful for correlating latch spikes.

```dql
timeseries growth_events = sum(custom.mssql.autogrowth.event_count),
    by: { event_name, database_name, file_name },
    from: now() - 6h
| filter arraySum(growth_events) > 0
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

## 6. Deadlock Events

List all deadlock events captured in the last 24 hours with their XML graph.

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

## 7. Correlation: Auto-Growth Events vs. Latch Wait Spikes

Overlay auto-growth event counts with latch wait time to identify if file
growth is the root cause of latch contention.

```dql
timeseries {
        latch_wait   = avg(custom.mssql.latch.wait_time_ms),
        growth_count = sum(custom.mssql.autogrowth.event_count)
    },
    from: now() - 6h
```

**Correlation: Blocking chain count vs. latch wait time:**

```dql
timeseries {
        latch_wait = avg(custom.mssql.latch.wait_time_ms),
        chains     = avg(custom.mssql.blocking.active_chains)
    },
    from: now() - 6h
```
