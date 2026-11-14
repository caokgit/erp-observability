# Runbooks

How to do each operation of the track **now**: complete, tested flows from prerequisites to verification and roll
back, each command followed by its real output and a `Check:` line. Revised in place; the journal holds what happened
([the rule](../../method/METHOD.md#living-docs-and-the-journal-never-mixed-owner-2026-10-25)). A page is written in the same step as its first
execution.

## Map

| Page | When | What |
|---|---|---|
| [deploy](deploy.md) | Once per environment, then on a change of the code or the image | Build round 1 from nothing: state, shared root and the path to Teams, the environment's root, the role, the image, the job |
| [respond](respond.md) | When a card arrives; once per round for a game day on dev | What every card's first steps lead to: one section per rule enabled on stg, its queries with real output, whom to call; the game day |
| [drills](drills.md) | After a deploy or a change of a rule, the routing or the card | Make each rule fire on dev (lowered values, a real lock wait) and time its card (A4, A5) |
| [aws-design](aws-design.md) | Before quoting the AWS design's numbers, or after a change to its guardrails | Rerun the cost estimate from both price lists and the SCP module's tests on a mock provider; nothing created |
| [pipeline](pipeline.md) | Before every push, at every session start, and on GitHub at every push | The CI steps on the laptop (`tools/ci.sh`), the policy gate inside `obs.sh plan`, `obs.sh drift` |
| public-export | At the end of every stage that changes what the public repo shows | Build the export, search it, publish it as the public repo's one commit |
| devsecops | After the ERP team ships an image or merges to `develop` | Read-only scans of the client's ERP source and stg's images; the counts for the findings page |
| [kubernetes-lab](kubernetes-lab.md) | To show or change the Kubernetes mapping | The lab on kind: the lab repo's charts, the demonstration Odoo, the translated rules, drills timed at the sink, the dashboard, down |
| [backtests](backtests.md) | Before a rule is deployed or changed | Run a log rule's own query over the workspace's history (A3), or once as the alert would |

## The operations script: tools/obs.sh

**[tools/obs.sh](../../tools/obs.sh) is every live operation of the track as one command each: it signs in with the
right login (az to create with `.scratch_az_write`, to read with `.scratch_az`; psql through the lab's service file),
reads names from the committed names files, keeps secrets in variables and never prints them, masks its output, and
names every Postgres session `obs-*`.** The runbooks call it; the usage list is the script's header.

| Subcommand | Does | Used in |
|---|---|---|
| `tf <root> <args>` | Any terraform command in `terraform/envs/<root>`, the write login | [deploy](deploy.md), steps 3 and 5 (init, import) |
| `plan <root>` | A saved plan, then [tools/no-repo-trace.py](../../tools/no-repo-trace.py) on what it would send to Azure, then the policies ([tools/policy.sh](../../tools/policy.sh) `plan`); a refused plan is deleted | deploy, drills, [pipeline](pipeline.md#3-the-plan-gate) |
| `drift` | Plans shared, dev and stg without a lock or a plan file: exit 0 when code and Azure match, 2 when a root differs | [pipeline](pipeline.md#4-drift), each session start |
| `apply <root>` | Applies exactly that saved plan | deploy, drills |
| `role <env> <admin service>` | [sql/obs_monitor.sql](../../sql/obs_monitor.sql) as the admin, the password sent only as a SCRAM verifier | deploy, step 6 |
| `role-check <env> <admin service>` | Acceptance A1 as `obs_monitor`, then the grants and their grantor | deploy, step 6 |
| `push <tag>` | Builds `job/`, scans the image, pushes `obs/sql-job:<tag>` to the stg registry | deploy, step 7 |
| `ag-test <env> <page\|ticket>` | Azure's test alert through an action group and its Logic App; shows the Logic App's last run | deploy, step 4 |
| `job <env> start\|list` | Starts a run of the SQL job, or lists its runs | deploy, step 8; drills |
| `kq '<KQL>' [duration]` | A query on the platform workspace | deploy, verify; drills |
| `kq-env <env> '<KQL>' [duration]` | The same, after the environment's apps, server and gateway as let statements, so the KQL names none | [respond](respond.md#3-any-query-without-names) |
| `drill-lock <reader service> <s>` | L1's drill: a real advisory-lock wait, no data touched | drills, step 3 |
| `inventory` | What the track has in Azure: resources, role assignments, tables, the image | [platform](../platform.md#what-the-track-has-added) |
| `trace-live`, `audit` | The no-GitHub check: tagged resources only, or every place the track wrote (resources, role assignments, state, the image's manifests, the workspace, the Activity Log, the Postgres application names) | deploy, after each apply |

## Template

The shared runbook page template, synced from the lab: [method/templates/runbook-page.md](../../method/templates/runbook-page.md).
