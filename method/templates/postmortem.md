# Template: a post-mortem

Written after an incident: what users felt, what happened in order, why the system allowed it, what the monitoring
saw, and what will change. Blameless: causes are looked for in the system, never in a person; nobody is named
(Google's [Postmortem Culture](https://sre.google/sre-book/postmortem-culture/), 2026-11-08). It is a record, like a
journal entry: frozen once reviewed, except its action items' states. Where it lives and who reviews it: the repo's
`AGENTS.md` or spec. Copy the block below.

````markdown
# Post-mortem: <YYYY-MM-DD>, <what users felt, in a few words>

<Status: being written / reviewed by <role> on <date>. Sources: <where every fact comes from: the workspace, a write-up, metrics>.>

## Summary

<Three to five lines: what users saw, for how long, the contributing causes in one sentence, what has changed since.>

## Impact

| | |
|---|---|
| Who | <users, journeys, teams> |
| How long | <from, to, in UTC; how the end was decided> |
| How much | <failed requests, jobs, data; real counts> |
| Detected by | <a person, an alert; the time> |

## Timeline

All times UTC. Each line names its source.

| Time | Event | Source |
|---|---|---|

## Contributing causes

<Why the system let it happen, as a chain: each link a fact with its evidence, then the gaps (what was missing that
would have stopped it). What was measured kept apart from what is inferred.>

## What the monitoring saw, and would see today

| Rule | Would it fire? | When, and how long after the start |
|---|---|---|

## What went well, what did not

## Action items

| # | Action | Kind (prevent, detect, mitigate) | Owner (a team or role) | State |
|---|---|---|---|---|

## Corrections

<Facts this post-mortem found wrong elsewhere (an earlier write-up, a doc), and where each was fixed.>
````
