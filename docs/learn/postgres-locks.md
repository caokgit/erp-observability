# Lock waits, lock timeouts and Odoo's retries

What happens when two of Odoo's transactions want the same row, what each step leaves in which log, and which of the
track's rules reads it. Round 1's L1 and round 4's in-progress reading watch the waits
([round 4](../specs/round-4.md#1-l1-while-the-wait-lasts)); round 5 adds the cancellations and Odoo's retries
([round 5](../specs/round-5.md)). The same rules on Prometheus: [prometheus-loki](prometheus-loki.md).

## The map

**One idea: on stg a statement that waits for a lock is cancelled by Postgres after 10 s; if it belongs to a web
request, Odoo runs the whole request again, up to 5 tries in all, so a user sees a slow save before a failed one; if it belongs
to background work, that work handles it its own way. Each step leaves a line in a different log.**

| Step | Who acts | What it leaves | Where | Read by |
|---|---|---|---|---|
| 1. The wait passes 1 s | Postgres (`log_lock_waits` on, `deadlock_timeout` 1 s) | `still waiting for ShareLock on transaction ... after 1000 ms` | The server's log (`PGSQLServerLogs`) | L1-burst counts them |
| 2. The wait is still going at a job run | The SQL job (`pg_locks.waitstart`, every 5 min) | A `lock_wait` row with the oldest wait | `OdooQueue_CL` | L1-wait (round 4) |
| 3a. The wait ends: the lock is granted | Postgres | `acquired ... after N ms` | The server's log | L1-wait pages over 60 s |
| 3b. The wait reaches 10 s | Postgres (`lock_timeout` 10 s on Odoo's role) | `ERROR: canceling statement due to lock timeout` | The server's log | **L1-burst, from round 5** |
| 4. The request is tried again | Odoo (`retrying()`, up to 5 tries) | `LOCK_NOT_AVAILABLE, 4 tries left, try again in 1.2 sec...` | Odoo's own log file | **The log reader's `lock_retry`, from round 5** |
| 5. The fifth try fails too | Odoo | `LOCK_NOT_AVAILABLE, maximum number of tries reached!`; the user gets an error | Odoo's own log file | **`lock_failed`; L1-burst tickets it** |

## Why a lock timeout exists

A row lock makes a second writer wait until the first transaction ends. Without a limit, the wait has no end: on
2026-08-20 a sync held a lock while workers piled up behind it, and stg answered 502 to everyone
([post-mortem](../postmortems/2026-08-20-stg-502-bursts.md)). The fix of 2026-08-25 was a `lock_timeout` of 10 s on
Odoo's database role: a write that cannot get its lock in 10 s is cancelled, so the worker is freed instead of held
([PostgreSQL: lock_timeout](https://www.postgresql.org/docs/17/runtime-config-client.html#GUC-LOCK-TIMEOUT),
2026-11-09). The price: the cancelled write must be done again, which is where Odoo's retries come in.

## One write followed (REAL, stg, 2026-11-08, UTC)

Two of Odoo's sessions, A and B, both want to write while a third transaction holds what they need. The server's log,
trimmed (sessions shortened; nothing else changed):

```text
17:16:35  A  still waiting for ShareLock on transaction 40915309 after 1000.072 ms
17:16:35  B  still waiting for AccessExclusiveLock on tuple (0,1) of relation 217413 ... after 1000.070 ms
17:16:43  B  still waiting ... tuple (0,1) of relation 217413 ... after 9129.258 ms
17:16:43  A  still waiting for ShareLock on transaction 40915309 after 9651.909 ms
17:16:44  A  ERROR:  canceling statement due to lock timeout
17:16:44  B  acquired AccessExclusiveLock on tuple (0,1) of relation 217413 ... after 9874.582 ms
17:16:45  B  still waiting for ShareLock on transaction 40915309 after 1000.123 ms
17:16:54  B  ERROR:  canceling statement due to lock timeout
```

A waited 10 s and was cancelled. B got the row lock just before its 10 s, then had to wait for the same holding
transaction, and was cancelled 10 s later. Relation 217413 is `spreadsheet_change_log`, a custom add-on's table
of about two rows (the catalog, read as the reader role on 2026-11-09).

```mermaid
sequenceDiagram
  participant U as User's request
  participant O as Odoo worker
  participant P as Postgres
  U->>O: save
  O->>P: UPDATE (try 1)
  Note over P: waits; at 1 s "still waiting"
  P-->>O: 10 s: canceling statement due to lock timeout
  O->>O: rollback, sleep random 0 to 2 s
  O->>P: try 2 (and so on, up to 5)
  alt a try gets the lock
    P-->>O: done
    O-->>U: saved, slowly
  else the fifth try is cancelled too
    O-->>U: error: maximum number of tries reached
  end
```

## What Odoo does with the cancellation

Odoo 19 runs each request inside `retrying()`. A `LOCK_NOT_AVAILABLE` error (the lock timeout's code), a serialization
failure or a deadlock rolls the transaction back, sleeps `random.uniform(0.0, 2 ** try)` seconds and runs the request
again, up to `MAX_TRIES_ON_CONCURRENCY_FAILURE = 5`
([odoo/service/model.py](https://github.com/odoo/odoo/blob/19.0/odoo/service/model.py), lines 28 to 30 and 160 to 230,
read 2026-11-09). The arithmetic of the worst case (**TOY**: every try waits its full 10 s):

| Try | Waits for the lock | Then sleeps (at most) | Elapsed (at most) |
|---|---|---|---|
| 1 | 10 s | 2 s | 12 s |
| 2 | 10 s | 4 s | 26 s |
| 3 | 10 s | 8 s | 44 s |
| 4 | 10 s | 16 s | 70 s |
| 5 | 10 s | fails | 80 s |

So a lock problem costs the user time long before it costs a failed save, and a request at 80 s is close to Odoo's
`limit_time_real` of 120 s, where the worker itself is ended (the pattern O1 watches).

## How often, on stg (REAL, measured 2026-11-09)

| Month (since the database moved, 2026-08-27) | Cancellations | 5-min bins with any | Bins over 12 | Most in one bin |
|---|---|---|---|---|
| August (from the 27th) | 27 | 13 | 0 | 4 |
| September | 1,640 | 419 | 1 | 14 |
| October | 6,328 | 1,571 (18 % of the month's bins) | 9 | 16 |
| November (to the 8th) | 596 | 189 | 0 | 8 |

What the waits were for, over the 30 days to 2026-11-08: 8,513 `still waiting` lines on a transaction (a row another
transaction changed and has not committed), 483 on the first row of `spreadsheet_change_log`, a few hundred on
its other rows. The add-on's own code describes the table as insert only, so that concurrent imports never wait for each other, but the add-on also prunes it with `DELETE` (the ERP source, read only), and a delete locks the rows it
removes: a pointer for the ERP team, not a finding the track can prove from the log alone.

### Web requests or background work? (REAL, 2026-11-09)

Step 4's line is written only for a **web request**: `retrying()` wraps requests, not queue jobs or scheduled tasks,
which handle a cancelled statement their own way. Odoo's log on the share is at DEBUG, so every retry line is there.
The log reader's `retries` mode counted them:

| Environment | Odoo's log read | `lock_retry` | `lock_failed` | Other retries | Other failures | The server's cancellations, same days |
|---|---|---|---|---|---|---|
| stg | 2026-10-31 to 11-07 (the rotated files the share keeps) | 0 | 0 | 0 | 0 | 590 |
| dev | 2026-10-01 to 11-07 | 23 (at most 8 a day, 11-04) | 0 | 35 | 0 | 43 on 11-04 alone |

So on stg the cancelled statements are not users' saves: they are background work (queue jobs, scheduled tasks; part
of it waits on the spreadsheet change log's rows, above), which retries or fails inside its own job. On dev a few web requests met a lock
timeout, and every one succeeded on a later try.

Which background work, on stg (REAL, 2026-11-09, a read-only probe over the same rotated files, counts only): lines
naming a lock timeout, `LockNotAvailable` or `postponed`, each credited to the logger of the line before it (a traceback
has no logger of its own, and workers interleave, so the split is approximate):

| Logger | Lines | What it is |
|---|---|---|
| `odoo.addons.queue_job.controllers.main` | 786 `postponed` (DEBUG) | Queue jobs that hit a concurrency error and were put back in the queue to run again: queue_job's own retry |
| A custom add-on's cache model | about 525 tracebacks with `LockNotAvailable` | The add-on's spreadsheet cache refresh, cancelled at 10 s |
| `odoo.sql_db` | 505 tracebacks | Odoo's database layer reporting the error (the same events, seen from below) |
| `queue_job` runner and channels; `ir_cron`; `ir_autovacuum`; `werkzeug`; the Service Bus client | 3 to 33 each | Scheduled tasks (the daily Auto-vacuum task among them), the job runner, a few inside web workers |

So the lock timeout mostly reschedules queue jobs and cancels the spreadsheet cache's refresh: work that is late, not a
user's save that is lost. The reader counts the web requests' retries; queue_job's `postponed` lines are a candidate
for its next kind (counted since round 6: 1,010 on stg's files from 11-01 to 11-10, 212 of them on 11-09). stg's log
file was empty from 2026-11-08 05:00 to 17:20 and is written in bursts since, so a day's
counts there are a floor.

**In our design:** [D27](../design.md#decisions) puts step 3b and step 5 on L1-burst's ticket and teaches the log
reader steps 4 and 5; [D26](../design.md#decisions) is step 2.
