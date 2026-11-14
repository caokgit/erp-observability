# Learn

Concept pages for the track. They teach and decide nothing; each section ends with
`**In our design:**` pointing to a decision in [design.md](../design.md). A page is written before the spec section
that first uses the tool, and extended whenever the owner asks a question
([AGENTS.md](../../method/METHOD.md#a-clarification-question-is-a-doc-bug)).

## Reading order

| # | Page | Covers | Status |
|---|---|---|---|
| 1 | [azure-monitor-alerts.md](azure-monitor-alerts.md) | Metric, log search and activity log alerts on the client's real signals; action groups; prices for Southeast Asia and round 1's arithmetic | written |
| 2 | [logs-ingestion-api.md](logs-ingestion-api.md) | Own rows into the workspace: the endpoint, the data collection rule, the `_CL` table, the role; what the client's workspace allows; the job's data cost | written |
| 3 | [container-apps-jobs.md](container-apps-jobs.md) | Apps and jobs in the stg Odoo environment; a scheduled job setting by setting; the secrets warning; the job's cost | written |
| 4 | [postgres-query-stats.md](postgres-query-stats.md) | `pg_stat_statements`, Query Store, `auto_explain` and the slow-statement log on the client's servers; one slow refresh through all four | written |
| 5 | [postgres-roles.md](postgres-roles.md) | The monitoring role: the three GRANTs door by door, what PUBLIC already has on dev, granting through the owner's role, the role's settings | written |
| 6 | [alert-flow.md](alert-flow.md) | Round 1 end to end: sources, the workspace, the rules, the alert, the action group, the Logic App, the Teams card; one alert followed with real times; the card file | written |
| 7 | [odoo-scheduled-tasks.md](odoo-scheduled-tasks.md) | Odoo's scheduled tasks (`ir_cron`), what L6 reads, and the daily cleanup that stopped on stg and dev | written |
| 8 | [postgres-autovacuum.md](postgres-autovacuum.md) | PostgreSQL's autovacuum: dead rows, when it starts, what stg's tables show, why the job reads the statistics | written |
| 9 | [odoo-logs.md](odoo-logs.md) | Odoo's log file on the share, its worker messages, what a killed worker leaves | written |
| 10 | [slo.md](slo.md) | SLIs, SLOs, error budgets and burn-rate alerts on stg's real traffic; one failed request followed to the page; 90 days of backtest; why no latency SLO yet | written |
| 11 | [aws-landing-zone.md](aws-landing-zone.md) | An AWS landing zone read from the client's Azure estate: organization, OUs, SCPs and IAM, Control Tower, AFT, the security baseline, the transit network, DR strategies | written |
| 12 | [policy-as-code.md](policy-as-code.md) | OPA, Rego and conftest on the track's Terraform: one forbidden resource followed through the source and plan gates; vs Kyverno and Azure Policy; drift and `-detailed-exitcode`; why CI never reaches Azure | written |
| 13 | [incident-response.md](incident-response.md) | Severities, when an alert becomes an incident, the roles, first steps on the card, blameless post-mortems, game days, on the client's 2026-08-20 and 09-09 incidents | written |
| 14 | devsecops-scanning.md | SAST, SCA, secrets, configuration and image scans on the client's ERP source and stg's images; reading 3,789 findings down to 3 with a fix; where scanning belongs in a pipeline | written |
| 15 | [prometheus-loki.md](prometheus-loki.md) | The track's rules on Prometheus, Loki and Grafana: PromQL and LogQL beside KQL, one sample followed to a notification, recording rules across two stores, exporters, `promtool` tests; why L1 pages during the wait here | written |
| 16 | [postgres-locks.md](postgres-locks.md) | Lock waits, the 10 s lock timeout and Odoo's 5 retries: one write followed through the server's log and Odoo's; what each step leaves, which rule reads it; stg's counts | written |
| 17 | [odoo-queue-job.md](odoo-queue-job.md) | Odoo's job queue: states, `eta`, retries, channels and stg's capacities; an import that dies mid-run and the queue 2 h behind, followed through L5; what L5 misses and round 7's change | written |

