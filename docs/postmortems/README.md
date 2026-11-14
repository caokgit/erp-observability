# Post-mortems

One page per incident in the client's ERP that users felt or that needed a second team: impact, a timeline with a source per
line, contributing causes in the system (never a person), what the track's rules saw or would see, and action items
with an owner and a state. Blameless and written from the raw data; the concepts are in
[incident-response](../learn/incident-response.md#blameless-post-mortems), the rule in the
[method](../../method/METHOD.md#living-docs-and-the-journal-never-mixed-owner-2026-10-25), the outline in the
[template](../../method/templates/postmortem.md). A page is frozen once reviewed, except its action items' states.

| Post-mortem | What users felt | Open action items |
|---|---|---|
| [2026-08-20](2026-08-20-stg-502-bursts.md) | Blank pages (two container kills, 84 and 113 502s), an afternoon of 502s, then the TV dashboards failing for 40 minutes | 5, 6: the Sync write out of the web request; the afternoon and evening explained (7, deploys on the alert path: done by round 4) |
| [2026-09-09](2026-09-09-stg-cron-memory.md) | Scheduled work stopped through the cron app's restarts (09-04, 07, 11); the web app killed three times on 09-09 | 4, 5: stg's Odoo log restored; probe kills against sync failures (3, the entrypoint's warning: done by round 4) |

From the game day of 2026-11-08 ([respond](../runbooks/respond.md#the-game-day-of-2026-11-08)), not an incident: a
lock wait still in progress paged nobody until it ended; since round 4 the SQL job reads the longest wait in progress
every 5 minutes, so L1 pages while it lasts ([round 4](../specs/round-4.md#1-l1-while-the-wait-lasts)).
