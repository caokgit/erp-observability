# Round 4: the post-mortems' items for the track

Stage R4 of the plan of 2026-11-08 ([roadmap](../design.md#roadmap), [D26](../design.md#decisions)): the three action items the
post-mortems and the game day left to the track ([post-mortems](../postmortems/README.md)). Status: built and live on stg on 2026-11-08 (the plan of 2026-11-08; live changes within the ground rules, never to data, dev
before stg, every plan read before its apply).

## What and why

**One idea: each item closes a gap a real incident or the game day showed, and all three fit inside what already
runs: a lock wait pages while it lasts (the job reads it, the existing L1 rule alerts on it), and one new ticket rule
puts deploys and the entrypoint's warnings on the same channel as the alerts.**

| # | Item | Gap it closes | Where it came from |
|---|---|---|---|
| 1 | **L1 pages while a wait lasts** | Azure's L1 reads the log line written when a wait ends; a wait in progress paged nobody | The game day of 2026-11-08 ([respond](../runbooks/respond.md#the-game-day-of-2026-11-08)); on Kubernetes the same rule fires during the wait ([mapping](kubernetes-mapping.md#the-rules)) |
| 2 | **A ticket on the entrypoint's warnings** | The cron app's entrypoint printed `WARNING limit_memory_hard=... >= container memory limit` at every start for 34 days, read by nobody | [2026-09-09](../postmortems/2026-09-09-stg-cron-memory.md), action item 3 |
| 3 | **Deploys on the alert path** | The 2026-08-20 evening's TV failures followed a deploy that no card showed | [2026-08-20](../postmortems/2026-08-20-stg-502-bursts.md), action item 7 |

## 1. L1 while the wait lasts

The SQL job reads, at each run, the lock waits in progress in its own database and writes one row to `OdooQueue_CL`
with `Check = "lock_wait"`: `Count` the sessions waiting, `OldestAgeSec` the longest wait so far. The source is
`pg_locks.waitstart` (PostgreSQL 14 and later: when the process began waiting), joined to `pg_stat_activity` only
for the database name:

| Choice | Why |
|---|---|
| `pg_locks`, not `pg_stat_activity`'s wait columns | `pg_stat_activity` hides other users' wait events from a role without `pg_read_all_stats`, which `obs_monitor` does not hold (`NOINHERIT`, two tables); `pg_locks` is readable by every role, so **no grant changes** |
| `waitstart`, not `query_start` | The wait's own start; a statement may wait only after running a while |
| The queue table's generic columns | No new table or DCR stream: a stream change is refused for up to 31 min after it ([known failure modes](../known-failure-modes.md)) |
| The existing L1-wait rule, not a new one | Its query adds the job's rows (`OldestAgeSec` over 60 s on the last run) to the log's finished waits; the same page, card and first steps; $0 more |
| L1-wait's window from 5 to 10 min, still every 5 min | The job's rows reach the workspace minutes after the run, so a 5-min window could pass a row before it is visible; L5 reads the same rows over 10 min for the same reason; the price depends on the frequency, not the window |

What it can and cannot see: the job runs every 5 minutes on stg, so a wait is seen only if it is still in progress
at a run. A wait over 5 minutes is always seen while it lasts; one of 1 to 5 minutes is seen with a chance of its
length over 5 minutes, and is still paged when it ends, from the log, as before. On stg, Odoo's own database role
carries a `lock_timeout` of 10 s (set 2026-08-25, [post-mortem](../postmortems/2026-08-20-stg-502-bursts.md)), so its
waits end at 10 s as `canceling statement due to lock timeout`: the reading pages a long wait only from a session
without that limit (another role, a maintenance or admin session); each cancellation is one try of a request, not a failed request: Odoo 19 retries a lock timeout up to 5 times with a random backoff and fails the request only after the fifth, logging `maximum number of tries reached!` in its own log ([`odoo/service/model.py`](https://github.com/odoo/odoo/blob/19.0/odoo/service/model.py), `MAX_TRIES_ON_CONCURRENCY_FAILURE = 5`, read 2026-11-09). No rule counts the cancellations yet (stg: 4,672 from 2026-10-10 to 11-08, measured 2026-11-09). Round 5 counts them ([round 5](round-5.md)); a reading more often than every 5 minutes was dropped there.

## 2 and 3. E1: the apps' deploys and entrypoint warnings

A new log rule **E1**, every 15 min, ticket ([kql/E1-changes.kql](../../kql/E1-changes.kql)): one row per app and bin
with the new revisions created (`RevisionCreation` in the system log) and the entrypoint's `WARNING` lines (console
lines starting `entrypoint: WARNING`; Odoo's own warnings and the docs build's are other lines). Its card says which:
a deploy is information on the same channel as the pages, so a responder sees "deployed at 10:23" beside a burst of
500s at 10:24; a warning is a configuration problem the ERP team fixes.

| Read on stg (2026-11-08, read only) | |
|---|---|
| New revisions, last 30 days | 28 on the web app, 29 on the cron app: about one deploy a day, both apps |
| `entrypoint: WARNING` lines, last 90 days | 256 on the cron app, 2026-08-20 14:55 to 09-23 06:58 UTC (one per container start), none since the cron app was resized on 2026-09-23 ([post-mortem](../postmortems/2026-09-09-stg-cron-memory.md)) |

## Cost

| Piece | A month (stg) |
|---|---|
| L1's query reads one more table | $0 (the same rule) |
| E1, every 15 min | $0.50 |
| One more row per job run | about 0.4 MB, under a cent |
| **Round 4** | **about $0.50**, so rounds 1 to 4 about **$19.50** against $20 ([D8](../design.md#decisions)) |

## Acceptance

| # | Check | How |
|---|---|---|
| F1 | This spec | Approved under the plan of 2026-11-08 |
| F2 | The job reads waits in progress | A dry run on dev during a held advisory lock shows the `lock_wait` row with the wait's age; no grant changed |
| F3 | E1's backtest | Over stg's 90 days: the entrypoint warning's days (2026-08-20 to 09-23) and the deploys |
| F4 | L1 pages during the wait, on dev | A 420 s wait; the dev job run twice during it; L1-wait's card before the wait ends |
| F5 | E1 on dev | A real deploy or restart on dev is not the track's to make, so the drill widens E1's window and lookback to 2 days (a drill override the alerts module gains; Azure caps a log alert's window at 2 days and limits its query to that window), reaching dev's last real deploy; its card arrives |
| F6 | stg live | The image and both rules applied after the plan was read, the repo-trace scan and the policies; `obs.sh drift` 0; `obs.sh audit` clean |
| F7 | Teardown | E1 in the teardown preview; the job's extra query leaves with the job |

## Teardown

E1 is one more Terraform rule per environment, removed with the alerts module (`plan -destroy`); the job's new query
goes with the job's image. No grant or setting was added.
