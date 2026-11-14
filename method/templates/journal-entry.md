# Template: a journal entry

One entry per session, in `docs/journal/YYYY-MM-DD-<slug>.md`, listed in the journal README ([the rule](../METHOD.md#living-docs-and-the-journal-never-mixed-owner-2026-10-25)). Copy the block below.

````markdown
# <YYYY-MM-DD>: <phase>, <topic>

## Summary

- **Goal:** <what the session set out to do, link to the status step>.
- **Outcome:** <done / partly / blocked, in one line, with the proving check>.
- **Docs changed:** <runbook and lab sections rewritten, with links>.
- **Incidents:** <count, each linked to its section below>.
- **Next:** <the step named in status>.

## Timeline

| Time | Step | Result |
|---|---|---|
| 09:40 | <step> | <ok / failed: see incident 1> |

## Steps

### <step>

```bash
<the command as run>
```

```text
<the real output, trimmed; secrets named by path, hostname and public addresses masked>
```

<what it showed, and the runbook section it became>

## Incident: <what>

| | |
|---|---|
| Seen | <time, symptom> |
| Impact | <what it cost or risked> |
| Cause | <root cause> |
| Fix | <what was done> |
| Prevention | <row in known-failure-modes, rule, check> |

<a timeline or diagram if the incident had several steps>
````
