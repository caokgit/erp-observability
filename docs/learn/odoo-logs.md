# Odoo's log file, and what a killed worker leaves in it

Where Odoo writes its log on the client's apps, what its lines look like, and the lines a killed or recycled worker leaves, for
round 2's rule O1 (the 2026-09-09 crash loop that left no trace on the platform). Previous:
[odoo-scheduled-tasks](odoo-scheduled-tasks.md); how a job reads the file: [one folder of a share](container-apps-jobs.md#reading-one-folder-of-a-file-share).

**One idea: Odoo runs a master process with worker processes; when a worker hits a limit or is killed, only Odoo's own
log says so, and on the client that log is a file on the share, at DEBUG level, which no Azure service reads.**

## Where the log is (REAL)

The apps log to a file under `/var/log/odoo`, the `log` folder of the app's share; their console carries almost nothing
(the lab's odoo-platform, read
2026-11-07: "Odoo logs to a file on the share (`/var/log/odoo`)", at DEBUG, about 12 GB). The stg cron app's memory
misconfiguration of 2026-08-20 to 09-23 (Odoo's hard limit above the container's) shows on the platform only as a
warning at each start and as restarts and probe kills on other days; a worker killed by the kernel inside a running
container leaves no container event, no exit 137 and no restart, only a line in this file
([post-mortem](../postmortems/2026-09-09-stg-cron-memory.md)).

## What a worker's end looks like

DOCS (Odoo 19 [server.py](https://github.com/odoo/odoo/blob/19.0/odoo/service/server.py), 2026-11-08, read through a
summarising fetch), the messages, quoted with their level:

| Event | Message | Level |
|---|---|---|
| Soft memory limit | `Worker (%d) virtual memory limit (%s) reached.` | INFO |
| CPU time limit | `Worker (%d) CPU time limit (%s) reached.` | INFO |
| Real time limit | `%s (%s) timeout after %ss` (e.g. `WorkerCron (123) timeout after 120s`) | ERROR |
| Recycled after its requests | `Worker (%d) max request (%s) reached.` | INFO |
| Exits | `Worker (%s) exiting. request_count: ...` | INFO |
| Removed by the master (any end, a SIGKILL included) | `Worker (%s) unregistered` | DEBUG |
| Exit code 3 | `Critial worker error (%s)` (sic) | CRITICAL |

A worker killed from outside (the container's memory killer, which the 2026-09-09 hard limit above the container's let
happen) writes nothing itself; the master only logs `unregistered`. So **a kill is an `unregistered` with no `exiting`
before it**; a limit is one of the limit lines. Rule O1 counts both.

One exception, found on dev's real log (**REAL**, 2026-11-08, the reader's `trace`): when the whole server stops (a
container stop or restart), the master logs `Multiprocess clean stop` and `Stopping workers gracefully`, then
unregisters every worker without their `exiting`. Counted naively, dev's October restarts made 200 "kill" bins; an
`unregistered` within 2 minutes after a shutdown line is therefore clean. Even then, 21 bins of such ends remained in
30 days, and the trace showed a worker unregistered at 02:25:14 that kept logging `polling for jobs` afterwards: an
`unregistered` alone is not proof of a kill on these servers. So O1 pages on the limits Odoo states itself; the inferred
kills are counted and kept for the ERP team's reading.

**In our design:** round 2's log reader and O1 ([spec](../specs/round-2.md#the-log-reader)).
