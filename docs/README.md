# docs/

Every page in `docs/`, once, grouped by what it is for. Start with the [README](../README.md), then the
[design](design.md).

## Decisions

| Page | What it holds |
|---|---|
| [design.md](design.md) | Context, decisions (D#), the roadmap, open decisions (O#), things to verify (V#) |
| [platform.md](platform.md) | The client's resources the track reads or adds to, by role, with the signal that uses each |
| [cost.md](cost.md) | What the track costs: billed against estimated, by resource and by round |
| [how-i-work.md](how-i-work.md) | The AI-assisted workflow, its rules, and the errors they caught |
| [known-failure-modes.md](known-failure-modes.md) | Real failure modes met in the track: symptom, cause, prevention, recovery |

## Specs

| Page | What it holds |
|---|---|
| [specs/round-1.md](specs/round-1.md) | Round 1: eight log signals (11 rules), five metric series and a heartbeat with their backtests; the SQL job; the monitoring role; Terraform; routing; cost; acceptance A1 to A10; teardown |
| [specs/round-2.md](specs/round-2.md) | Round 2: query cost (Q1), table bloat (T1), Odoo's workers killed (O1), the dev view refresh (R1); the table statistics, the log reader; cost; acceptance B1 to B8; teardown |
| [specs/round-3.md](specs/round-3.md) | Round 3: an availability SLO for stg's web app per journey (99.5 % over 30 days) and its two burn-rate rules; incident response: each card's meaning and first steps, the respond runbook, post-mortems, the game day; acceptance C1 to C13; teardown |
| [specs/round-4.md](specs/round-4.md) | Round 4: L1 pages while a lock wait lasts (the job reads `pg_locks`, no grant); E1 tickets deploys and entrypoint warnings; acceptance F1 to F7 |
| [specs/round-5.md](specs/round-5.md) | Round 5: lock-timeout cancellations on the ticket path, Odoo's retries counted by the log reader; acceptance G1 to G7 |
| [specs/round-6.md](specs/round-6.md) | Round 6: L7 counts restarts, not exit records (a false page in the first 24 h); E1 names the new revision; the log reader counts postponed jobs; tickets post no resolve card; acceptance I1 to I9 |
| [specs/round-7.md](specs/round-7.md) | Round 7: the job-queue page fires when the queue as a whole is behind (2 or more channels late); one stalled channel and jobs found dead are tickets; a job's wait counts from when it could run; acceptance N1 to N9 |
| [specs/pipeline.md](specs/pipeline.md) | The IaC pipeline: CI on every push (offline), the ground rules as Rego policies on the source and on every plan, drift at each session start; acceptance P1 to P7 |
| [specs/kubernetes-mapping.md](specs/kubernetes-mapping.md) | Stage K: the track's rules in PromQL and LogQL on kind with a lab's monitoring charts, a demonstration Odoo that reproduces the incident patterns, drills timed at Alertmanager's receiver; acceptance K1 to K7 |
| [specs/devsecops.md](specs/devsecops.md) | DevSecOps: SAST, SCA, secret, configuration and image scans of the client's ERP source and images, read only; the ranking; SAST in this repo's CI |
| [specs/aws-migration.md](specs/aws-migration.md) | Azure to AWS: the landing zone (accounts, OUs, five SCPs), the network, compute and data, observability on AWS, DR tiers, cost against Azure from both price lists, showback, the waves and estimate, ADR-1 to ADR-5; a paper design |

## Learning, doing, and the record

| Page | What it holds |
|---|---|
| [learn/](learn/README.md) | Concept pages with the system's real values, and their reading order |
| [runbooks/](runbooks/README.md) | How to do each operation now, every command with its real output |
| [postmortems/](postmortems/README.md) | One blameless post-mortem per real incident: timeline from the workspace, causes, what the rules would see, action items |
| [postmortems/2026-08-20-stg-502-bursts.md](postmortems/2026-08-20-stg-502-bursts.md) | 2026-08-20: two container kills (84 and 113 502s), an afternoon of 502s, the TV dashboards failing after a deploy |
| [postmortems/2026-09-09-stg-cron-memory.md](postmortems/2026-09-09-stg-cron-memory.md) | 2026-09-09: the cron app's memory guard that could not fire for 34 days, its probe-kill days, the corrections to the incident list |
| [reviews/round-1.md](reviews/round-1.md) | Round 1's review: the proof (A1 to A10), what it taught |
| [reviews/round-2.md](reviews/round-2.md) | Round 2's review: query cost, table bloat, Odoo's log; the proof (B1 to B8) |
| [reviews/round-3.md](reviews/round-3.md) | Round 3's review: the SLOs and incident response; the proof (C1 to C13), what the post-mortems and the game day corrected |
| [reviews/round-4.md](reviews/round-4.md) | Round 4's review: L1 while a wait lasts (the job reads `pg_locks`, no grant), E1 for deploys and entrypoint warnings; the Kubernetes lab's contrast; the proof (F1 to F7) |
| [reviews/round-5.md](reviews/round-5.md) | Round 5's review: lock timeouts found unwatched, measured to queue jobs and a cache refresh rather than users' saves; round 2's rules on Kubernetes (G1 to G7, K8 to K10) |
| [reviews/round-6.md](reviews/round-6.md) | Round 6's review: the first 24 h judged alert by alert, the false page traced and fixed; the reader's trailing-space miss; the hand-closed alert that blocks its rule (I1 to I9) |
| [reviews/round-7.md](reviews/round-7.md) | Round 7's review: one dying import paged 14 times; now one ticket, with the page kept for a queue behind (N1 to N9) |
