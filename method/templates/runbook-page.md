# Template: a runbook page

One page per operation, in `docs/runbooks/`, on the map in the runbooks README ([the rule](../METHOD.md#living-docs-and-the-journal-never-mixed-owner-2026-10-25)). Copy the block below.

````markdown
# <Operation>

Stage <n> of the [map](README.md): <what it does, one or two lines, links to the decision>.
Last verified: <YYYY-MM-DD>.

## Overview

<a Mermaid diagram of the steps and what each one produces>

## Prerequisites

| Needs | Check | If not |
|---|---|---|
| Where and mode: <office / home, VPN on or off>; <Auto / Manual> | | |
| <e.g. SSH to the box> | `ssh -F $PWD/.scratch_ssh/config gpu-box true` exits 0 | [reach-the-box](reach-the-box.md) |

## Steps

### 1. <step>

Why: <one line>.

```bash
<command>
```

Output (REAL, <date>):

```text
<trimmed output>
```

Check: <what proves this step worked>.
If you see <symptom>: <what to do> ([row](../known-failure-modes.md)).

## Verify end to end

<one test that proves the whole operation, with its output>

## Roll back

<the undo for each step, in reverse order>
````
