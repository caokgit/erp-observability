# Round 5: lock-timeout cancellations and Odoo's retries

Stage C of the plan of 2026-11-08 ([D27](../design.md#decisions)). Round 4 found that on stg Odoo's role ends every lock wait at 10 s
([round 4](round-4.md#1-l1-while-the-wait-lasts)); this round watches what that leaves behind. Learn first:
[postgres-locks](../learn/postgres-locks.md). Status: built, then live on dev and stg on 2026-11-08 (UTC), dev before stg, every plan read before its apply.

## What and why

**One idea: a lock wait on stg no longer pages as a long wait, because Postgres cancels it at 10 s and Odoo retries the
request; so the track counts the cancellations (heavy contention, a ticket) and Odoo's own retry lines (the requests a
user lost, a ticket at the first one), with no new rule, table or grant.**

| # | Item | Gap it closes | Source |
|---|---|---|---|
| 1 | **Cancellations in L1-burst** | 4,672 `canceling statement due to lock timeout` lines on stg in 30 days, counted by no rule; L1-wait cannot see them (no wait passes 10 s) | The server's log |
| 2 | **Odoo's retries in the log reader** | Whether a cancellation cost the user anything is only in Odoo's own log (`maximum number of tries reached!`), which nothing counted | Odoo's log file on the share (the Azure Files share Odoo writes its log to) |

Not done, and why: reading lock waits in progress more often than every 5 minutes (a candidate after round 4). On stg
Odoo's own waits cannot pass 10 s, so a faster sample would mostly see waits that are about to be cancelled anyway;
the log already pages a long wait by any other session when it ends (the plan of 2026-11-08, 2026-11-09).

## 1. Cancellations in L1-burst

L1-burst ([kql/L1-lock-waits.kql](../../kql/L1-lock-waits.kql)) already tickets a burst of `still waiting` lines. Its
log part also counts, per 5-min bin, the `canceling statement due to lock timeout` lines (`Cancelled`), and the burst
condition becomes: more than `MinStillWaiting` waiting lines, **or more than `MinCancelled` cancellations**, or at
least `MinFailed` failed requests (item 2).

| Choice | Why |
|---|---|
| L1-burst, not a new rule | Rounds 1 to 4 cost about $19.50 of D8's $20; a new 15-min rule costs $0.50; the same query file, card and runbook section |
| A ticket, not a page | Each cancellation is one try Odoo repeats; heavy contention makes requests slow before it makes them fail |
| `MinCancelled` 12 per 5 min | stg's 90 days ([learn](../learn/postgres-locks.md#how-often-on-stg-real-measured-2026-11-09)): p99 per bin 8 to 12 by month; bins over 12: September 1, October 9, November 0; the backtest below counts the tickets |
| L1-wait unchanged | Its `long_wait` kind ignores the new counts; its backtest must stay as A3 found it |

## 2. Odoo's retries in the log reader

The log reader ([job/log_scan.py](../../job/log_scan.py)) counts four new kinds in Odoo's own log, from the logger
`odoo.service.model` only (so no other line can match), into `OdooLog_CL` as today:

| Kind | Odoo's line | Means |
|---|---|---|
| `lock_retry` | `LOCK_NOT_AVAILABLE, N tries left, try again in ...` | A request lost a try to the lock timeout and is tried again |
| `lock_failed` | `LOCK_NOT_AVAILABLE, maximum number of tries reached!` | A request failed after 5 tries: a user saw an error |
| `concurrency_retry` | The same with `SERIALIZATION_FAILURE`, `DEADLOCK_DETECTED` or another retried error | Another concurrency error, tried again |
| `concurrency_failed` | The same, `maximum number of tries reached!` | Another concurrency error, failed |

L1-burst also fires on `lock_failed` of at least `MinFailed` (1) in its window: a request a user lost to a lock is worth
a ticket on its own. A new mode `retries <date>` prints those kinds per day over the files on the share since a date,
read only, as `backfill` does for O1.

What it can and cannot see: the reader reads the share's current log file each run; stg's was empty from
2026-11-08 05:00 to 17:20 and is written in bursts since (an ERP team item), so on stg the counts are a floor; `retries` reads the
rotated files too (the share keeps 2026-10-31 onwards). Measured 2026-11-09 ([learn](../learn/postgres-locks.md#web-requests-or-background-work-real-2026-11-09)):
stg 0 retry lines of any kind from 10-31 to 11-07, so its cancellations are background work, not web requests; dev 23
lock retries and 35 others since 10-01, none failed. `lock_failed` stays in the rule: it is the one count that means a
user saw an error.

## Cost

$0 more: no rule, table, stream or grant; the reader's rows grow by at most four a run, only when a retry happened.
Rounds 1 to 5 stay at about $19.50 a month against $20 ([D8](../design.md#decisions)).

## Acceptance

| ID | Check | Pass |
|---|---|---|
| G1 | The spec | Approved before the build |
| G2 | L1-burst's backtest on stg since 2026-08-27 | Its new tickets fall on the days the cancellations peak; the number of firing bins a month is recorded; the old burst bins still fire (A3, round 1's backtest check) |
| G3 | The drill on dev | L1-burst enabled with a window override reaching dev's real cancellations and a lowered `MinCancelled`; it fires and its card arrives; dev idle after |
| G4 | stg's preflight | L1-burst run once as the alert on stg's live data: quiet, or a firing judged a catch |
| G5 | stg live | Applied after a plan read first; `obs.sh drift` 0; `obs.sh audit` clean |
| G6 | Teardown | The teardown preview's rows unchanged (73): only queries and the image change |
| G7 | The reader's kinds | A unit test on Odoo 19's own lines passes in CI; `retries` on stg's rotated files and a dry run on dev print the counts |

## Teardown

Nothing new to remove: the kinds go with the reader and the condition with L1-burst, both in round 1's and round 2's
[teardown](round-1.md#teardown) rows.
