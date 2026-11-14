# Round 6: count restarts, not exit records; E1's new revision; queue_job's postponements; fewer cards

[D28](../design.md#decisions). Round 1's A7 failed on 2026-11-09: L7 paged a single restart of stg's cron app
as a crash loop ([round 1's spec](round-1.md#acceptance), the reading).
This round fixes that condition, makes two smaller corrections the same reading and round 5 found, and, at the owner's
request after the cards kept coming (2026-11-10), stops the resolve card for tickets. Status: approved 2026-11-10
(revised that day before approval), built dev before stg, live on stg 2026-11-10 07:46 UTC ([review](../reviews/round-6.md)).

## What and why

**One idea: a rule must count the thing it means. L7 means "the app keeps restarting", but it counted exit records,
and one restart writes 3 to 9 of them. The other three items have the same flaw on a smaller scale: E1's card names the
wrong revision, queue jobs that were rescheduled are not counted at all, and every ticket posts a second card that
nobody acts on.**

| # | Item | Gap it closes | Source |
|---|---|---|---|
| 1 | **L7 counts restarts** | 11 of the 18 bins over L7's crash-loop count since 2025-11 were one restart (10 restarts, one split across two bins), so they were false pages. One of them paged on stg at 2026-11-09 02:23 UTC | The apps' system log |
| 2 | **E1 names the new revision** | A `RevisionCreation` record carries the outgoing revision's name, so the card said 2977 for the deploy that brought 2980 | The same log |
| 3 | **The reader counts `postponed`** | queue_job reschedules a job that lost a lock (786 times on stg from 10-31 to 11-07), and nothing counts it ([round 5](../reviews/round-5.md#7-what-the-next-round-inherits)) | Odoo's log file on the share |
| 4 | **Tickets post no resolve card** | Each alert posts a card when it fires and another when it resolves: stg's 7 alerts from 2026-11-09 02:19 to 11-10 03:37 made 14 cards, 6 of them tickets resolving | The Logic Apps (shared root) |

Not changed, and why:
- **A deploy while E1's alert is open sends no card.** A log alert is stateful: it fires once, then stays open until
  it resolves. The respond runbook says to read the hour's `RevisionCreation` rows
  ([respond, E1](../runbooks/respond.md#e1-a-deploy-or-an-entrypoint-warning)). A stateless E1 would never resolve on
  its own.
- **L2-499.** It ticketed 43 abandoned requests at 2026-11-09 11:24 UTC, all from one Android browser signature
  reloading the login page; no 5xx. Its threshold fires rarely (bins a month: August 32, September 1, October 2,
  November 1), so it stays as it is.

## 1. L7 counts restarts

The crash-loop part of [kql/L7-app-terminations.kql](../../kql/L7-app-terminations.kql) changes. Before, a bin fired
on `ProcessExited` at `MinExited` (3) or more. Now it also needs **`MinRestarts` (2) or more containers named `main`
created** (`ContainerCreated`, `Created container 'main'`) in the same app and bin. Out of memory (exit 137) and probe
kills (2 or more) are unchanged. A single restart stays M1, M2's ticket.

What one restart and one loop look like in the log (REAL, measured 2026-11-09 over every 15-min bin since 2025-11-01):

| Case | `ProcessExited` | `main` created | Bins | Example |
|---|---|---|---|---|
| One restart (after a probe kill or a crash) | 3 to 9, within 2 to 14 s | 0 or 1 | 11 | stg's cron app, 2026-11-09 02:15: 9 exits in 13 s, one container |
| A crash loop | 15 to 26 | 3 to 20 | 7 | 07-22 07:45 (20, during 3 deploys), 07-27, 08-27 twice, 09-12, 10-07, 10-22 |
| A deploy | 0 (one bin: 18, the 07-22 loop) | 2 to 5 | 63 | Every roll of 2026-11-09 |
| A probe-kill loop, or restarts without exits | 0 to 2 | 2 to 4 | most of the other 188 (of 268 bins with 3 exits or 2 restarts) | The cron app on 08-01 to 08-02, 08-25, 09-07, 09-11: paged by the probe-kill part |

| Choice | Why |
|---|---|
| Exits **and** restarts, not restarts alone | Restarts alone fire on every deploy (2 to 5 `main` created) and on every probe-kill bin, which the probe-kill part already pages. Exits keep the rule's meaning (the process dies), and restarts drop the single restart |
| `MinRestarts` 2 | Every single restart has at most one `main` created, and every loop has 3 or more; 2 leaves a margin for a loop split across two bins |
| No deploy exclusion | The worst loop on record (07-22 07:45, 20 restarts) ran during 3 deploys; excluding deploy bins would miss it |

## 2. E1 names the new revision

[kql/E1-changes.kql](../../kql/E1-changes.kql) takes the card's `Revision` from the bin's `PulledImage` records of the
image `main` whose revision is not the outgoing one. When the bin has none (the image was cached, or pulled in the next
bin), the card says the revision it replaced. Measured over a year of deploy bins (2026-11-09): 379 bins; 314 with one
new revision pulled, 47 with several (a restart or a second roll in the same bin), 18 with none.

## 3. The reader counts `postponed`

The log reader ([job/log_scan.py](../../job/log_scan.py)) adds a kind `postponed`: queue_job's controller rescheduled
a job instead of failing it (a `RetryableJobError`, or a retryable database error such as a lock timeout). The kind is
counted from queue_job's controller logger only, at DEBUG, as stg's log is. Its exact line is read from OCA queue_job's
source for Odoo 19 ([`controllers/main.py`, `_runjob`](https://github.com/OCA/queue/blob/19.0/queue_job/controllers/main.py) and
[`job.py`, `Job.__repr__`](https://github.com/OCA/queue/blob/19.0/queue_job/job.py), read with curl 2026-11-10): `<Job <uuid>, priority:<n>> postponed`,
which stg's file writes with a trailing space. It is counted, not alerted: it shows
how much background work a lock costs, beside L1-burst's ticket, and no rule changes. `retries <date>` prints it
with the other four kinds.

## 4. Tickets post no resolve card

The card's Logic App ([terraform/envs/shared/main.tf](../../terraform/envs/shared/main.tf)) posts only when the alert
fired, or when a **page** (Sev1) resolved: whoever was paged sees it end. A ticket (Sev3) that resolves posts nothing;
Azure keeps its state and time, and the respond runbook reads them there. The run still happens and is recorded, so a
card's delay stays measurable. The filter is per environment, so dev takes it first and stg after its drill.

## Cost

$0 more: two queries and one Logic App action change, and the reader writes at most one more row a run. Rounds 1 to 6 stay at about $19.50 a
month against $20 ([D8](../design.md#decisions)).

## Acceptance

| ID | Check | Pass |
|---|---|---|
| I1 | The spec | Approved before the build |
| I2 | L7's backtest on stg since 2025-11-01 | The 7 loop bins fire through the crash-loop part, and no other bin: none of the 11 single restarts, no deploy; the probe-kill and OOM parts' bins unchanged |
| I3 | A7's replay | L7 over 2026-11-08 07:25 to 11-09 07:25 UTC: no row |
| I4 | E1's backtest on stg since 2026-10-10 | Each row's revision is the new one: 2980, 2981 and 2982 on 2026-11-09 |
| I5 | The reader's kind | A unit test on queue_job's line passes in CI; `retries` on stg's rotated files matches a count of the same lines by round 5's probe over the same files (786 over 10-31 to 11-07 then; the share keeps about a week, so both run on the files present) |
| I6 | Drill on dev | L7 and E1 fire on dev through a 2-day window over dev's real events, L7 with lowered values when dev holds no loop (`MinExited` 0, `MinRestarts` 1: a deploy's new containers), and each card arrives; then back to real values while enabled until each resolves (round 5's step); dev idle, no alert open |
| I7 | stg live | Applied after a plan read first: only the two rules, the two jobs' image and stg's card filter change; `obs.sh drift` 0; `obs.sh audit` clean; the teardown preview unchanged (73 rows) |
| I8 | A7's rerun | 24 h on stg from I7's apply with no false page, read in a later session; A7 itself stays failed. **Passes** (2026-11-10 07:46 to 11-11 07:46 UTC, read 2026-11-14): 10 alerts, 3 pages and 7 tickets, each a catch: L7 on revision 3012's crash loop on both apps (7 and 8 restarts), L5-page twice on a queue behind (865 jobs waiting 2 h 7 min for their first run; `root.endpoint` finishing nothing for 4 h while one job's worker died at each of its 7 attempts), E1 on 5 deploys, `M-restarts` on both apps' loop ([review](../reviews/round-6.md#2-what-it-delivered)) |
| I9 | Fewer cards | On dev, then stg: a page's fire and resolve post two cards; a ticket's fire posts one and its resolve none, while the Logic App's run is recorded `Succeeded`. **Passes** on stg too (A7's rerun window): 8 tickets' resolves `post=Skipped` (E1 ×5, `M-restarts` ×2, L6), the 2 pages' resolves posted, 20 runs `Succeeded` |

## Teardown

Nothing new to remove: the conditions go with L7 and E1, the kind with the reader, and the filter with the Logic Apps,
all in the existing [teardown](round-1.md#teardown) rows.
