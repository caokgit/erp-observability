# The method

The working rules shared by the owner's repos: the lab (the source) and its siblings. Each repo's
`AGENTS.md` imports this file (`@method/METHOD.md`) and adds only its own rules; where the two differ, the repo's
`AGENTS.md` wins. **The method grows wherever the work happens:** edit it in the repo you are working in, then share
it the same session ([keeping the method in step](#keeping-the-method-in-step)).

**Never add a `CLAUDE.md` or `CLAUDE.local.md`** to a repo, or to any folder above it: if either exists, Claude Code
stops reading `AGENTS.md` by default ([Claude Code memory](https://code.claude.com/docs/en/memory.md), checked
2026-11-08).

Every fact found along the way (a probe, a measurement, a service fact, a source) is written down in the matching doc,
never only in chat.

## Rule 0: spec first

Nothing is implemented before its spec section exists in `docs/`. A commit that touches an implementation path (listed
in the repo's `tools/repo.toml`) carries a trailer `Spec: docs/<file>.md#<anchor>`; `tools/hooks/commit-msg` rejects
the commit when the trailer, the file or the anchor is missing. Docs-only commits need no trailer.

When writing the code shows that an approved spec is wrong or incomplete (a limit of the platform, a case it did not
cover), fix the spec first, in a docs commit of its own, then write the code; list each change for the owner at the next
stop, so an approval never covers a design that silently moved (2026-11-08: an Azure log alert has one severity, so a
signal with a page part and a ticket part became two rules).

## Spec and code never duplicate each other

- **The spec owns** design, decisions (with the why), contracts between components, and acceptance criteria.
- **The code owns** how things are implemented and behave: config values, flags, schemas, versions, commands.
- A doc **links to the file** instead of restating what the file says. A doc that restates code is a doc bug: replace
  the copy with a link.
- When code and spec disagree on behaviour, the code is the truth about *what happens*; fix the spec if the design
  changed, or fix the code if it drifted from the design.

## A clarification question is a doc bug

Whenever the owner asks about a concept or about something built, however small: answer in chat **and** in the same
turn add or extend a section in the matching `docs/learn/<topic>.md`, add a row to the question finder in
`docs/learn/README.md`, then commit. A learn section:

- opens with `Asked on <YYYY-MM-DD>: "<the question>"`,
- teaches, decides nothing, and ends with `**In our design:**` pointing to decision IDs (D#),
- labels examples **REAL** (captured in the repo's own work, dated), **DOCS** (from vendor docs), **PLANNED**, or
  **TOY** (invented numbers that only show the arithmetic),
- explains the concept **and its purpose** (why it exists, what it is for here), then demonstrates it with **real
  values from the repo's own work** (a record, a measured number, a real config value) and a diagram or figure;
  invented values are marked **ILLUSTRATIVE** and used only when no real one exists (owner, 2026-10-21),
- uses a Mermaid diagram when a flow is involved; a colour SVG diagram in `docs/learn/diagrams/` is welcome to connect
  components and flows on one picture, rendered and checked before commit (owner, 2026-10-29).

The template: [method/templates/learn-section.md](templates/learn-section.md).

Every new tool gets a learn page **before** its spec section. Real values come first in every example (owner,
2026-10-21, confirmed 2026-10-30): a value seen here teaches more than a made-up one. An answer covers the whole set the
question points at, not only the example named (owner, 2026-11-07: "apart from 502, are there other codes?").

Videos suggested for a topic go into Videos to watch (`docs/learn/README.md#videos-to-watch`), in watching order,
with what each prepares for and a "Watched" column the owner updates (owner, 2026-10-28).

The owner asks ad-hoc questions in other sessions too, so `docs/learn/` grows from several places. Before adding a
section, read the question finder and the pages it touches: extend or link instead of repeating, merge overlaps, and
fix any fact a later finding made stale. Reorganising pages for a better learning path is welcome (owner, 2026-10-22).

## Sources sit next to the content

Every external fact, and every paper or doc used to explain a concept, carries its source link and access date in the
same paragraph or table row, so the owner can go back to it to study: `... ([source](https://...), 2026-10-18)`. No
separate reference lists. If a source was read through a summarising tool, say so and copy exact quotes from the live
page before quoting. Prices come from a price list or API that shows the numbers (Azure's pricing pages show "$-" to a
fetch; its Retail Prices API shows the prices).

## Sessions

- **One Claude Code session per step** (a build step, an experiment run, a round of drills). Start from the repo, not
  from memory: read `AGENTS.md`, `docs/status.md`, `git log --oneline -15`, `git status`.
- End a step with docs updated, the session's journal (`docs/journal/README.md`) entry closed, checks green, a commit,
  and the next session's setup (`docs/status.md#next-session-setup`) rewritten in `docs/status.md`: the mode to
  start in, where the owner must be, and the prompt to paste. Journal times come from `date +%H:%M` run in the same
  command that writes the row, never estimated. A session ends with no method warning from `tools/check-docs.py`
  (every method edit pushed, every newer source pulled).
- **A phase or round ends with its review** (owner, 2026-10-31: a careful review strengthens the content and the
  owner's knowledge; checking it against its sources finds errors the other pages hide): the story in one read,
  linking to the spec, runbooks, journal and learn pages and never copying them. The outline:
  [method/templates/review.md](templates/review.md); where it lives: the repo's `AGENTS.md`.

### Modes

Claude Code's permission mode is chosen by the owner when a session starts and switched as the work changes:

| Work | Mode |
|---|---|
| Reading, docs, learn pages, read-only probes | **Auto** |
| A live change outside the repo (a machine, a cloud resource, a database, GitHub settings) | **Manual**: every command waits for the owner, on top of the rule to show each change first |
| Choosing between designs before a spec exists | Normal work, the spec shown for approval; **Plan mode** only when the owner asks or several options must be weighed first |

- A session never starts in Plan mode by default. Plan mode with the owner is proposed whenever a choice needs
  planning: reorganising the docs, or several ways of doing a step (owner, 2026-10-30).
- When the work moves to the next row, say so **before** the first command of that row, and wait.

## Plans

Every revision of a session plan is saved as `.private/plans/plan-vN.md` (tracked in git), never overwritten; the numbering
runs across all the owner's repos (the next number after the highest in any of them). Plan mode can write only its own
plan file, so when a plan is revised in plan mode, save the previous revision the moment plan mode exits, and tell the
owner. Decisions that survive go into `docs/design.md`.

## Safety basics

- **Classifier block:** if a command is blocked by the auto-mode safety check, stop, say what was blocked and why it is
  needed, and ask the owner to switch to Manual mode. After they confirm, run the **same** command again. Never reshape
  a command to get past the check. Long scripts go in a scratch file run as `bash <file>`, not `bash -c` (the shell is
  zsh, which does not split unquoted variables into words).
- **Secrets** never appear in a file, commit, log or chat, not even a prefix. Name a secret by its path or key only.
  Inspect credential files by names and shapes; read private notes by their headings and never print a section that
  holds credentials (a mask that catches only labelled values misses a password alone on its line, 2026-11-07).
  Private notes and credentials live in `.private/`, gitignored except `.private/plans/`, so a plan holds no secret.
- **Live changes outside the repo** are shown first as their dry run (`--check --diff` for a playbook, `terraform plan`,
  the SQL about to run), with the runbook section they will land in, and run only after the owner says go. A change to
  a shared system goes to its rehearsal copy first (dev before stg, the lab before the box).
- **Cleaning something live:** edit the value in place first and delete only after, because a soft-deleted copy (a
  storage account, a key vault) keeps what it had when deleted; and before saying a value is gone, check every place it
  was written (the resource, its role assignments, state files, image manifests, logs, the activity log), not only the
  resource. An audit log that cannot be edited is recorded, not fought (2026-11-08).
- **Wrappers fail closed:** a script that wraps a live change (plan then apply, build then push) stops at the first
  failed step and leaves nothing behind for the next step to act on: a failed plan deletes its plan file, and apply
  refuses without a fresh one (2026-11-08: a failed plan left the previous one, which apply then applied). Show each
  plan, then apply it in a separate step, never chained.
- **Every tool login gets its own gitignored config folder**, re-exported on each command; credential files are mode
  600. Which folder each tool uses is in the repo's `AGENTS.md`.

## Git

- Concise commit subjects in plain English; prefix `docs:` for docs-only commits.
- **No `Co-Authored-By` or other AI attribution lines** (the hook rejects them).
- Never `--no-verify`. Push without asking only when it is a fast-forward of `main`.

## Writing

- No em dashes (`tools/check-docs.py` rejects them). Short sentences, tables for comparisons.
- Values stay real; what is never written (secrets, hostnames, which addresses and ids) is set by the repo's `AGENTS.md`
  and checked by `tools/check-docs.py` per `tools/repo.toml`. Output that can hold such values goes through
  `tools/mask.py` and a check by eye.
- What the docs never write stays out of committed code too: a read-only discovery script finds each resource by its
  role and writes the names into gitignored files that the code and the tools read; the same script writes the mask
  words (2026-11-08).
- Folder structure is not frozen: improve it when it stops fitting. Move with `git mv`, rewrite every link, run
  `python3 tools/check-docs.py`, never leave a stub.

### How a doc reads (owner, 2026-10-24)

Docs are revised often, so every revision keeps them clear, not only correct:

- **Ordered.** A page opens with what it is for and where it fits (one or two lines, links to its neighbours). Then the
  overview, then the detail: what, why, how, examples. One topic per section; headings a reader can scan.
- **Demonstrated.** Every concept or claim comes with a concrete example, real values first, then a table for
  comparisons and a diagram for flows (owner, 2026-10-31: "better than a million words").
- **Connected.** Link the page that holds a fact instead of repeating it; link back from where the reader would look
  for it (the question finder, the design).
- **Current, never appended.** Revise the section a new fact changes, do not add a paragraph below the old one: rewrite
  the sentence, update the number and its date, delete what is superseded (git keeps the history). When a fact changes,
  search the docs (of every repo that holds it) for its old value and fix every copy. Measured numbers carry their
  date; data that keeps changing says so.
- **Re-read before committing.** Read the whole section as a newcomer would: does it flow, does each step lead to the
  next, is anything stale or said twice?
- **Explained by following one thing (owner, 2026-10-25).** An explanation opens with the **one idea** that explains
  everything, in one bold sentence. Then it follows one concrete thing (a packet, a record, a request, a command, an
  alert) through each case in order: what fails first, then each change and what it fixes and what it does not. One
  small diagram per case, plain words before terms (each term defined in a short clause where it first appears), what
  was measured kept apart from what cannot be seen, and a side-by-side table of all cases at the end. The model:
  what went wrong with the office VPN.
- **One story per page, not a pile of answers (owner, 2026-10-27).** Content may be rich, but every part connects.
  Pages grow one question at a time, so every time a section is added, re-read the **whole page** and fix its flow:
  open with a map (a diagram or table of the pieces and how they connect), order the sections so each builds on the
  one before, say in each section how it links back to the map, merge facts said twice, and move background to the
  end. A question's `Asked on` line stays with the section that answers it, even when sections are merged. The model:
  python-packaging.

### Living docs and the journal: never mixed (owner, 2026-10-25)

A repo keeps a track record of every step and every incident, **and** docs that read as one complete, current flow.
Those are two kinds of page, and an event never goes into a living doc:

| | Living docs | Journal |
|---|---|---|
| Answers | How things are, and how to do them, **now** | What happened, **when**, in what order |
| Pages | `design`, `specs/`, `learn/`, runbooks/ (`docs/runbooks/README.md`), known-failure-modes (`docs/known-failure-modes.md`), and the repo's fact pages | journal/ (`docs/journal/README.md`)`YYYY-MM-DD-<slug>.md`, one per session |
| Changes | Revised in place ([how a doc reads](#how-a-doc-reads-owner-2026-10-24)) | Written during its session; **frozen** after the session's last commit (only broken links are fixed) |
| Commands | The current, tested way: copy-pasteable, with the expected output and a check | What was actually run, with the real output trimmed, **failed attempts included** |
| Incidents | `known-failure-modes`: one row per failure mode, updated when it recurs | The incident as it happened: timeline, impact, how it was found, the fix, a link to the row |

- **Every step** done in a session is in its journal entry, with the command and its real output. Every step meant to
  be repeated ends up in a **runbook**, rewritten until it is the complete flow from prerequisites to verification and
  rollback. The journal links to the runbook section; a runbook never says "on 2026-10-25 we ran".
- **Every incident** (something broke, a wrong assumption cost time, a secret showed in output, a command was blocked)
  gets a journal section `Incident: <what>` and a `known-failure-modes` row, new or updated, that links to it.
- **An incident in the system a repo watches or runs** (users felt it, or a second team was needed) gets a
  **blameless post-mortem** on the [post-mortem template](templates/postmortem.md): impact, a timeline with a source per
  line, contributing causes in the system (never a person, and nobody named), what the monitoring saw, action items
  with an owner and a state. It is a record like the journal: frozen once reviewed, except its action items' states.
  Where post-mortems live: the repo's `AGENTS.md` (2026-11-08: two real ones showed that writing them from the raw
  data also corrects earlier write-ups).
- **Runbooks call the code, they never copy it** ([spec and code](#spec-and-code-never-duplicate-each-other)): an
  automated step is one command naming its file; the runbook adds what code cannot hold: the order, prerequisites, how
  to verify, how to roll back.
- **Runbooks cover the whole journey (owner, 2026-10-30).** `docs/runbooks/README.md` is the map; pages are cut by how
  often they run. Each page is **read and revised as a whole**, one complete flow; shows every command **followed by
  its real output** (dated, trimmed, masked) and a `Check:` line; weaves each incident met into the step where it
  happens, as an "If you see ..." line linked to its `known-failure-modes` row; and is **written in the same step as the
  execution**, before the next step starts, never after the phase.
- **Teardown grows with the work (owner, 2026-10-30):** whatever a repo adds to a system it does not own, or grants for
  its sake, gets its removal in the same commit that adds it: a row in the spec's teardown inventory and the step that
  removes it. The scope of teardown is set in the repo's `AGENTS.md`.
- **Both read well.** A journal entry opens with a summary (goal, outcome, what changed in which doc), so nobody has to
  read the timeline to know the result; then a timeline table, the commands, and a diagram or a measured table wherever
  one explains faster than prose. The templates: [journal entry](templates/journal-entry.md),
  [runbook page](templates/runbook-page.md).
- Commands and outputs in both follow [safety basics](#safety-basics) and [writing](#writing).

## Keeping the method in step

The method has one reference copy, in the lab, and grows from every repo that uses it:

| You are in | To change the method | To take others' changes |
|---|---|---|
| The lab | Edit `method/` or a shared tool, check, commit | Nothing: it is the reference |
| A sibling | Edit `method/` or a shared tool, check, then `bash tools/sync-method.sh push "<what changed>"`: it commits the change in the lab, naming this repo, and updates this copy | `bash tools/sync-method.sh` (pull), then commit |

- **Shared or own?** A rule about how we work (docs, learn pages, the journal, sessions, git, plans, safety habits)
  goes in this file; a rule about the system a repo touches (a machine, a cloud estate, an application) goes in that
  repo's `AGENTS.md`; per-repo settings go in `tools/repo.toml`.
- **Both sides changed the same file:** `push` refuses and names it; merge it by hand into the lab, then pull.
- `tools/check-docs.py` warns about an edit not yet pushed and about a newer method not yet pulled; a session ends
  with neither.
