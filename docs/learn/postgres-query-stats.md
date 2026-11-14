# Postgres query statistics: pg_stat_statements, Query Store, auto_explain

Which queries cost the client's servers the most, and why: the tools a later round would build on for the CPU incidents of
2026-08-04 and 08-26 (round 1 does without them, [D4](../design.md#decisions)). Previous: [Container Apps Jobs](container-apps-jobs.md).

**One idea: the three tools answer the same question at three depths. `pg_stat_statements` keeps running totals per
query shape since the last reset; Query Store keeps the same totals cut into 15-minute windows for 7 days;
`auto_explain` writes the plan of each slow statement into the log, the "why".**

| | `pg_stat_statements` | Query Store (Azure) | `auto_explain` | Slow-statement log |
|---|---|---|---|---|
| Records | Calls, total and mean time, rows, blocks per normalized statement | The same per 15-minute window, per user, database and query id; waits if sampling is on | The plan of each statement over a duration | The statement and its duration |
| Kept | Until reset or evicted | 7 days in `azure_sys` (`pg_qs.retention_period_in_days`) | In the server log | In the server log |
| On the client's servers (**REAL** 2026-11-07) | Loaded and collecting on all three | `top` on all three; runtime rows in the workspace | Available, not loaded | On, at 1 s, on all three |

## pg_stat_statements: running totals per query shape

"The `pg_stat_statements` module provides a means for tracking planning and execution statistics of all SQL statements
executed by a server." Queries that differ only in constants share one row: "the constant is replaced by a parameter
symbol, such as `$1`" ([PostgreSQL 17 docs](https://www.postgresql.org/docs/17/pgstatstatements.html), 2026-11-07).

| Rule from the docs | On the client's servers (**REAL**) |
|---|---|
| Must be in `shared_preload_libraries`, "a server restart is needed to add or remove the module" | Already preloaded, with `pg_cron`, on all three: no restart needed to use it |
| `pg_stat_statements.max` (default 5000): past it, "information about the least-executed statements is discarded", counted in `pg_stat_statements_info.dealloc` | 5000; about 4,900 rows in each Odoo database, `dealloc` 1,145 on dev and 621 on stg since 2026-10-07 |
| "only superusers and roles with privileges of the `pg_read_all_stats` role are allowed to see the SQL text and `queryid` of queries executed by other users. Other users can see the statistics" | The reader sees the numbers, not the text: 4,871 of 4,878 rows hidden on dev. The monitoring role needs `pg_read_all_stats` for this (round 2) |

## Query Store: the same totals, in time windows

Query Store is Azure's flight recorder for PostgreSQL queries: what each query cost, window by window, kept for days, so
a slow hour can be traced to the query behind it.

"Query store automatically captures a history of queries and runtime statistics ... Data for all users, databases, and
queries is stored in a database named `azure_sys`"; windows of `pg_qs.interval_length_minutes` (default 15), up to 500
distinct queries per window; "Anyone in the PostgreSQL public role can use these views"
([Query Store](https://learn.microsoft.com/en-us/azure/postgresql/monitor/concepts-query-store), 2026-11-07).

**REAL** (2026-11-07): the runtime rows reach the workspace, `PGSQLQueryStoreRuntime` for the prd server (48,000 rows in a
day) and `AzureDiagnostics` for dev and stg (55,591), with `QueryId`, `DatabaseId`, `Calls`, `TotalExecDurationMs` and
block counts, **but no SQL text**: the text categories are enabled and sent no rows in 30 days. So the workspace can rank
query ids by time per database (the stg database by its oid), and the text comes from `azure_sys`.

**A warning that applies today:** "Don't enable query store on the Burstable pricing tier as it causes performance
problems." The dev and stg servers are Burstable B1ms and run with `pg_qs.query_capture_mode = top` (**REAL**); the prd
server, General Purpose, is fine. A finding for the platform team, not a change for this track.

### The stg database, hour by hour

What the workspace alone can say about stg's query cost, for round 2's rule Q1 (**REAL**, `PGSQLQueryStoreRuntime`,
`DatabaseId` 127276, 2026-10-09 to 2026-11-08, read 2026-11-08):

| Measure | Value |
|---|---|
| Rows, distinct query ids | 1,261,449 rows, 641,470 query ids |
| Database time per hour, the whole database | median 4.5 min, p95 69.1 min, max 106 min (2026-11-03 14:00 UTC) |
| Hours over 60 / 75 / 90 min | 51 / 27 / 7 (the 7 on 6 days) |
| One query, 7 days | id `-2426753535470534697`: 17,023 calls, 4.6 s each, 1,308.6 min (about 3 h a day) |
| Per query and hour over 20 min | 232 in 30 days: too many for a rule |

The prd server has 2 vCPUs, so 120 min of database time in an hour is both cores busy the whole hour; 90 min is three
quarters of the server for one database out of 20. The per-query numbers name the culprit once an hour is flagged; the
text stays on the server (`azure_sys`), looked up by its id.

**In our design:** round 2's Q1 ([spec](../specs/round-2.md#signals)).

## auto_explain: the plan behind a slow statement

"The `auto_explain` module provides a means for logging execution plans of slow statements automatically";
`auto_explain.log_min_duration` is "the minimum statement execution time ... that will cause the statement's plan to be
logged", `-1` by default ([PostgreSQL 17 docs](https://www.postgresql.org/docs/17/auto-explain.html), 2026-11-07).

| Rule from the docs | On the client's servers (**REAL**) |
|---|---|
| Loaded per session by a superuser (`LOAD`), or for all sessions through `session_preload_libraries` or `shared_preload_libraries` | In the allowed values of `shared_preload_libraries`, its 13 parameters present; adding it there means a restart of the server. Whether Azure offers `session_preload_libraries` was not checked ([V6](../design.md#to-verify)) |
| `auto_explain.log_analyze`: "per-plan-node timing occurs for all statements executed, whether or not they run long enough to actually get logged. This can have an extremely negative impact on performance" | Not to be turned on on the shared prd server; plans without `ANALYZE` show the chosen plan, not actual times |
| `auto_explain.sample_rate` explains only a fraction of statements | A way to keep the cost down |

## Following one slow statement through the four tools

The dev refresh of the materialized view `lot_stock_view` took **1,712 s** once in the last 30 days, on a 5-minute
schedule (**REAL**, from the slow-statement log). Each tool sees it differently:

| Tool | What it shows of that refresh |
|---|---|
| Slow-statement log | One line: `duration: 1712...ms statement: REFRESH MATERIALIZED VIEW CONCURRENTLY lot_stock_view`, at the time it ended |
| `pg_stat_statements` | One row for the refresh shape: calls, total time, mean time since 2026-10-07; the 1,712 s run is averaged in |
| Query Store | That run's window shows a high `MaxExecDurationMs` for the refresh's query id, so the slow window can be found |
| `auto_explain` (if loaded) | The plan of that run: which scan or join took the time |

**In our design:** [D4](../design.md#decisions) (round 1 needs none of these; query cost by family is planned for a later round, with `pg_read_all_stats` for the monitoring role), [V6](../design.md#to-verify).
