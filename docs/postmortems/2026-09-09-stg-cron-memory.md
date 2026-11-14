# Post-mortem: 2026-09-09, stg's cron app, a memory guard that could not fire

Status: written 2026-11-08 from the workspace (S4); for the
ERP and platform teams' review. Sources: the platform workspace (`ContainerAppConsoleLogs_CL`: the cron app's
entrypoint and Odoo lines; `ContainerAppSystemLogs_CL`: probes, kills, starts, revisions), the `RestartCount` and
`WorkingSetBytes` metrics, the rules' backtests, and the platform team's write-up of 2026-09-23 (the owner's infra
notes, outside this repo). Nobody is named; all times UTC. Template:
[method/templates/postmortem.md](../../method/templates/postmortem.md).

## Summary

The incident list records "an OOM crash loop, 59 times, from 2026-09-09" on stg's cron app (the app that runs every
Odoo scheduled task and queue job), caused by Odoo's hard memory limit set above the container's memory, and fixed by
resizing the app on 2026-09-23. **The workspace confirms the misconfiguration and the fix, but not the loop as
recorded:** the warning behind the "59 occurrences" is printed at **every container start** (256 starts from
2026-08-20 to 09-23, counted as 59 inside a 14-day query); the cron app's real kill days were 09-04, 09-07 and 09-11
(health probes timing out, 47 kills), on days when its memory stayed at or under 78 % of the limit; the one day its
memory reached the limit (09-15) had no restart. On 09-09 itself the cron app had no kill; the **web** app was killed
three times. Today L7 pages on those probe kills (this post-mortem's action item) and M2 tickets each restart.

## Impact

| | |
|---|---|
| Who | The cron app's work: scheduled tasks and queue jobs (imports from on-prem, the TV milestones); no user page is served by it. On 09-09, users of the web app (its own kills) |
| How long | The misconfiguration: 2026-08-20 14:55 to 2026-09-23 06:58 (34 days). Kill episodes: 09-04 03:45 to 04:15, 09-07 12:45 to 15:30, 09-11 07:45 to 09:00 |
| How much (REAL) | 47 `ProbeFailure` kills and 53 restarts (`RestartCount`) of the cron app from 09-04 to 09-13; 32 `ProcessExited` on 09-12 and 13; scheduled work stopped during each restart (the queue then held no history: the SQL job began on 2026-11-08) |
| Detected by | Found on 09-11 as an active crash loop while investigating sync failures; nothing alerted |

## Timeline

| Time (UTC) | Event | Source |
|---|---|---|
| 2026-08-20 14:55:50 | The cron app's entrypoint prints, for the first time: `WARNING limit_memory_hard=2684354560 >= container memory limit 2147483648B - Odoo's memory guard cannot fire before the platform OOM-kills this container` | Odoo lines |
| 08-20 to 09-23 | The warning repeats at each start: 256 lines; per day, exactly the number of `main` containers started (for example 09-07: 25 and 25; 09-11: 21 and 21) | Odoo lines, system log |
| 09-04 03:45 to 04:15 | 8 probe kills, 8 restarts | System log, `RestartCount` |
| 09-07 12:45 to 15:30 | 24 probe kills, 23 restarts; memory at most 1.46 GiB (73 %); the same day, the sync's connection resets (the 2026-09-07 incident) | System log, metrics, incident list |
| 09-09 | The cron app: 2 starts (revision updates), no kill, memory peak 1.77 GiB (89 %). The web app: 3 probe kills from 11:26 to 11:42, 502s on both journeys (SLO-fast's 11:45 episode) | System log, nginx lines, metrics |
| 09-11 07:45 to 09:00 | 15 probe kills, seen as a crash loop; memory at most 1.56 GiB (78 %); the same day, the VPN rekey incident (2026-09-11) | System log, metrics, write-up |
| 09-12 17:00, 09-13 10:30 | 25 and 6 `ProcessExited` in 15 min (the container's process exited, not killed by Azure) | System log |
| 09-15 | Memory peak 2.01 GiB: at the container's limit; no restart, no kill that day | `WorkingSetBytes`, `RestartCount` |
| 09-23 07:04 | The app resized from 1 vCPU / 2 GiB to 2 vCPU / 4 GiB; the last warning at 06:58:37, none since | Write-up, Odoo lines |

## Contributing causes

Measured:

1. The cron app's container had 2 GiB; Odoo's per-worker hard memory limit was 2.5 GiB, so Odoo's own guard (which
   ends a worker cleanly, with a log line) could never act before the kernel's memory killer.
2. The entrypoint detected this and said so at every start, in a line nobody read: no rule, no dashboard.
3. A worker killed by the kernel inside a running container leaves no container event, no exit 137 and no restart
   ([odoo-logs](../learn/odoo-logs.md#what-a-workers-end-looks-like)); only Odoo's log file shows it, and the files on
   the share start on 2026-10-31.

Not supported by the data: that the kills of 09-04, 09-07 and 09-11 were memory kills. They were Azure's kills after
three failed health probes, on days the container used 73 to 78 % of its memory; two of them fall on the days of the
sync incidents (09-07 connection resets, 09-11 the VPN rekey). **Inferred, to check:** workers blocked on dead
connections to on-prem, so none answers the probe (the 2026-08-20 mechanism, with a network wait instead of a lock
wait). The day memory reached the limit (09-15) is the one most likely to hold kernel kills of single workers, and it
left no platform trace at all.

## What the monitoring saw, and would see today

| Rule | Would it fire? | When |
|---|---|---|
| L7 (page), as built in round 1 | Yes, twice | 09-12 17:00 (25 exits), 09-13 10:30 (6) |
| L7 with this post-mortem's change (2 or more probe kills in 15 min) | Yes | 09-04 03:45; 09-07 12:45 to 15:15 (one alert, open for the episode); 09-09 11:30 (the web app); 09-11 07:45 to 08:45 |
| M2 restarts (ticket) | Yes | Each of 09-04, 07, 11, 12, 13 |
| O1 workers at their limits (page) | Unknown | It reads Odoo's statements of a limit; with the hard limit above the container's, Odoo states nothing for a kernel kill; and stg's log file has been empty since a rotation on 2026-11-08 |
| Anything on the warning line | No rule reads it | Action item 3 |

## What went well, what did not

| Went well | Did not |
|---|---|
| The entrypoint already compared the two limits and printed a clear warning | The warning ran for 34 days before anyone read it |
| The resize removed the misconfiguration (2.5 GiB under 4 GiB) | The write-up's count came from a 14-day query, so its start date was the query's edge, not the problem's |
| | "OOM" was assumed from the warning; the kills' days do not show memory pressure |

## Action items

| # | Action | Kind | Owner | State |
|---|---|---|---|---|
| 1 | Resize the cron app so the hard limit sits under the container's memory | Prevent | ERP team | Done 2026-09-23 |
| 2 | L7 pages on 2 or more `ProbeFailure` kills in 15 min ([round 1, L7](../specs/round-1.md#signals)) | Detect | The track | Done 2026-11-08 (S4) |
| 3 | A ticket rule on the entrypoint's `WARNING` lines (a configuration check that reads no secret) | Detect | The track | Done 2026-11-08: E1 ([round 4](../specs/round-4.md)) |
| 4 | Restore stg's Odoo log file, so O1 sees worker ends again | Detect | ERP team | Open |
| 5 | Check whether the cron app's probe kills follow sync failures to on-prem (timeouts on the sync's connections) | Learn | ERP team, platform team | Open: asked |

## Corrections

- "OOM crash loop, 59 times" (the incident list) and "recurring since at least 2026-09-09": the warning counted
  container starts, 256 from 2026-08-20; the kills were probe kills on 09-04, 07 and 11. Fixed in the lab's
  odoo-platform.
- "Left no trace in `RestartCount`" (round 1's spec, the discovery): `RestartCount` shows 53 restarts of the cron app
  from 09-04 to 09-13, none on 09-09 itself, which is the day the earlier backtest looked at; fixed in
  [round 1, L7](../specs/round-1.md#signals).
