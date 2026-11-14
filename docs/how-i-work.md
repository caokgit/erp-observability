# How I work

The track is built with an AI coding agent under written rules ([AGENTS.md](../AGENTS.md), [the method](../method/METHOD.md)).
This page says what those rules are for, and shows the cases where they caught a real error before it shipped or
corrected a record everyone believed.

**One idea: the agent is fast, so the rules make every step checkable: a spec before code, a plan before every live
change, real output in every runbook, and checks that refuse what a rule forbids. Speed without them would ship
confident mistakes; with them, the mistakes surface as a failed check, a wrong number in a backtest or a plan that does
not match.**

## The rules, and what each is for

| Rule | What it prevents | How it is held |
|---|---|---|
| A spec before code, with acceptance criteria | Code that solves a problem nobody agreed on | The commit hook refuses a code commit without a `Spec:` trailer naming an existing anchor ([hook](../tools/hooks/commit-msg)) |
| A spec found wrong is fixed first, in its own commit, and the change listed for the owner | An approval that silently covers a design that moved | [Method, rule 0](../method/METHOD.md#rule-0-spec-first) |
| Every external fact with its source and date in the same paragraph | Claims nobody can check | Review against the sources at each round's end |
| Every live change shown as its plan first, dev before stg | A change to a shared production system nobody saw | `obs.sh plan` writes the plan, the policies and the repo-trace scan check it, `obs.sh apply` applies only that plan |
| Runbooks written as each step first runs, with its real output | Docs that describe what someone meant to do | Every runbook command is followed by its output and a `Check:` line |
| Nothing in Azure names the repo | The working repo's name leaking into a client's tenant | Rego policies on every plan; `obs.sh audit` reads every place the track wrote |

## Cases where the rules caught an error

### A stale plan applied to stg

A Terraform plan failed, but the wrapper printed the error and left the previous plan file; the apply that followed
applied that older plan at 07:00:54 UTC, and the stg job and 16 rules went live before the monitoring role existed. A
plan from the fixed code removed the job and disabled the rules by 07:09:32; no stg alert fired. The fix became a rule of the method, **wrappers fail closed**: a failed plan deletes its
plan file, and apply refuses without a fresh one ([known failure modes](known-failure-modes.md)).

### The platform's limit changed the spec, before the code

The round 1 spec gave one signal a page part and a ticket part. Writing the Terraform showed that an Azure log alert
has one severity. The spec was fixed first, in its own commit (each such signal became two rules over one query), and
the change was listed for the owner, so the approval never covered a design that had moved
([round 1, signals](specs/round-1.md#signals)).

### Two post-mortems corrected the incident record

The incident list said the cron app had an "OOM crash loop, 59 times since 09-09". Written from the workspace's raw
lines, the [post-mortem](postmortems/2026-09-09-stg-cron-memory.md) found that the warning counted was printed at
**every container start** (256 times from 2026-08-20), that "since 09-09" was the edge of a 14-day query, and that the
real kills were probe kills on 09-04, 07 and 11. The [other one](postmortems/2026-08-20-stg-502-bursts.md) found a
second, uncatalogued failure on 2026-08-20 (every TV poll answered 500 for 40 minutes after a deploy), which a backtest
had filed under the morning's incident.

Both pointed at the same gap: **no rule paged on probe kills**, the cause of most of the kills. L7 now pages on 2 or
more in 15 minutes; its backtest found 204 more bins, all from July to September, none since October
([round 1, L7](specs/round-1.md#signals)).

### The real log corrected a rule twice

Round 2's O1 rule counts Odoo workers killed at their limits. The first backfill found hundreds of "kills" on dev: the
master's own graceful shutdown unregisters every worker without their exit line. Excluded, the rule then counted
inferred kills, until a worker was seen logging after its "unregistered" line. O1 now alerts only on the limits Odoo
itself states ([learn: Odoo's logs](learn/odoo-logs.md)).

### A hostname slipped through the mask

Output that may hold names goes through [tools/mask.py](../tools/mask.py). A Referer field in an nginx line carried an
app's public hostname, which the mask words did not hold. It showed only in the terminal; the discovery script now adds
every app's ingress name and custom domains to the mask words, and output is still read by eye.

### The repo's name in the first live tags

The first resources were tagged `repo = <account>/<repo>`, before the rule that nothing in Azure names the repo. The
tags were edited in place before any delete (a soft-deleted copy keeps its tags), and `obs.sh audit` now checks every
place the track writes. Two Activity Log events from that first hour stay: the Activity Log cannot be edited, so they
are recorded, not fought ([learn: what Azure keeps](learn/alert-flow.md#what-azure-keeps-of-what-the-track-did-and-whether-it-can-be-deleted)).

## What the agent does, and what stays with me

| The agent | Me |
|---|---|
| Reads the system (read-only probes, the workspace's history), writes the specs, the code, the runbooks and the reviews | Approves each spec and each plan for a live change; decides the trade-offs ([decisions](design.md#decisions)) |
| Runs the checks, the backtests and the drills, and records their real output | Agrees the ground rules with the client's teams; owns every change to their system |
| Proposes the next step from the open items | Chooses it |
