# AGENTS.md

Rules for any coding agent (Claude Code, Codex, ...) working on this track. Claude Code reads this file natively.
**Never add a `CLAUDE.md` or `CLAUDE.local.md`**: if either exists, Claude Code stops reading this file by default.

The track designs, builds and runs **monitoring and alerting for a manufacturer's live ERP**: Odoo on Azure Container
Apps, its PostgreSQL servers, and the VPN to on-premises, Azure-native, from the outside and the database only.
Deployments run from the laptop straight to Azure. This public repo is an anonymized export of the working repo
([D24](docs/design.md#decisions)); the rules below are the working repo's, in public names.

## The shared method

The rules shared with the owner's lab (spec first, spec and code, questions into learn pages, sources, sessions, modes,
plans, safety basics, git, how a doc reads, living docs and the journal) are in [method/METHOD.md](method/METHOD.md),
imported here:

@method/METHOD.md

**The method grows here too** ([D16](docs/design.md#decisions)): an improvement made in this repo is shared with the
lab in the same session. A rule about the client's system (Odoo, Azure, Postgres) stays in this file instead. This
file adds only the track's own rules; where the two differ, this file wins.

## Ground rules of the track (owner, 2026-11-07)

- **Odoo's code, image, config and deploys are never touched** (the ERP team's rule). No restart or revision change of
  an Odoo app.
- **stg is watched; dev is the rehearsal ground**: every alert is fired on dev on purpose first, every Postgres change
  tried on dev first ([D1](docs/design.md#decisions)).
- Allowed: Postgres settings and roles (dev first; a restart of the shared prd server only in a window agreed with the
  platform team); new Azure resources for monitoring; read-only access to every Postgres server's data.
- **Terraform creates monitoring resources only** and reads existing ones as data sources; it never manages a
  resource the platform owns.
- **Nothing in Azure or on a Postgres server names the GitHub repo** (owner, 2026-11-08, critical): no tag, name,
  description, query text, image file or label, setting or comment the track puts there holds the GitHub account, the
  repo's name or a path inside the repo. Tags are `owner = observability-track` with `env` or `purpose`; the KQL files'
  comments are dropped when a query is rendered; a file shipped in the image names no repo path. Every plan goes through
  [tools/no-repo-trace.py](tools/no-repo-trace.py) before it is applied, and `bash tools/obs.sh audit` checks every place
  after (resources, role assignments, state, the image's manifests, the workspace, the Activity Log, the application
  names our Postgres sessions leave in the server's log: each names itself `obs-*`). To clean a live resource, edit it
  in place first and delete it only after: a soft-deleted copy keeps its tags (2026-11-08).
- **The client's application code may be cloned into the working repo** ([D14](docs/design.md#decisions)), only the
  parts a simulation needs; it is fixed and tested there, never pushed back, and never published.

## Rule 0 in this repo

Implementation paths: `terraform/`, `kql/`, `job/`, `sql/`, `tools/`, `policy/`, `.github/`, `k8s/`
([tools/repo.toml](tools/repo.toml)).

## Sessions and logins

- One session per step, as in the [method](method/METHOD.md#sessions); a step here is a build step or a round of
  drills. **A round ends with its review** in `docs/reviews/<round>.md`, on the method's
  [review template](method/templates/review.md).
- **Logins are shared with the lab**, by absolute path, so one sign-in serves both repos and nothing is written to `~`:

  | Tool | Isolation |
  |---|---|
  | az | `AZURE_CONFIG_DIR=$HOME/lab/.scratch_az` (the client's tenant, device code): reads |
  | az, to create resources | `AZURE_CONFIG_DIR=$HOME/lab/.scratch_az_write`: the account that may create the track's resources; Terraform and `terraform/state-storage.sh` run with it |
  | psql | `PGSERVICEFILE=$HOME/lab/.scratch_pg/pg_service.conf PGPASSFILE=$HOME/lab/.scratch_pg/pgpass`, then `psql service=<name>`; reader services only unless a change is approved |
  | gh, git push | The repo's local git config calls the lab's `gh` with its own config folder |
  | terraform | `TF_DATA_DIR` and the plugin cache under `.scratch_tf/` (gitignored) |

  Credential files are mode 600. Long scripts go in a scratch file run as `bash <file>`, not `bash -c`.

### Which mode a session runs in

| Work | Mode |
|---|---|
| Reading, docs, learn pages, read-only probes of Azure and Postgres, KQL queries | **Auto** |
| A live change: any Azure resource, a Postgres role or setting, `terraform apply` | **Manual**: every command waits for the owner, each change shown first (`terraform plan`, the SQL), unless the owner authorizes a session to run unattended within these rules |
| Choosing between designs before a spec exists | As in the [method](method/METHOD.md#modes) |

## Safety and approvals

The basics (the classifier block, secrets, live changes shown first) are in the
[method](method/METHOD.md#safety-basics); the track adds:

- **Network reach:** from home, the client's VPN is needed for the Postgres servers.
- **Live changes** (Azure resources, Postgres, alert rules) are shown first and run only after the owner says go;
  **dev before stg**, always.
- **Private notes** hold credentials; they are read by headings only.

## Writing

The basics and [how a doc reads](method/METHOD.md#how-a-doc-reads-owner-2026-10-24) are in the method; the track adds:

- **Never written:** subscription, tenant or workspace IDs, resource ID paths (the checker rejects GUIDs and
  `/subscriptions/` paths), IP addresses, hostnames, and the names of Postgres servers and Container Apps (each is the
  first label of a hostname): write "the prd server", "the stg web app". Also never: passwords, tokens, people's
  names. Output that may hold any of these goes through [tools/mask.py](tools/mask.py) and a check by eye.
- **The files Terraform reads** (the names that `terraform/names.sh` discovers, each root's `backend.hcl`, the alert
  routes with the Teams workflow URLs) are committed in the working repo only; this public repo holds example files of
  the same shape.
- **Teardown** covers everything the track adds to Azure and Postgres: a row in the spec's teardown inventory in the
  same commit, as in the method's [living docs and the journal](method/METHOD.md#living-docs-and-the-journal-never-mixed-owner-2026-10-25).

## What goes where

| Path | Holds |
|---|---|
| [docs/README.md](docs/README.md) | The index of every page in `docs/` |
| [docs/design.md](docs/design.md) | Context, decisions D#, the roadmap, open decisions O#, things to verify V# |
| [docs/platform.md](docs/platform.md) | The client's resources the track reads or adds to, by role |
| `docs/specs/` | One spec page per component: design, contract, acceptance |
| [docs/learn/](docs/learn/README.md) | Concept pages and their reading order |
| [docs/runbooks/](docs/runbooks/README.md) | How to do each operation now, with real output |
| [docs/known-failure-modes.md](docs/known-failure-modes.md) | One row per real failure mode |
| `docs/reviews/` | One review per round, written at its end |
| [docs/postmortems/](docs/postmortems/README.md) | One blameless post-mortem per real incident |
| `terraform/`, `kql/`, `job/`, `sql/` | Monitoring resources, alert queries, the SQL job, the monitoring role's SQL |
| `k8s/` | The Kubernetes mapping's lab: the rules in PromQL and LogQL, the demonstration add-on, the manifests ([spec](docs/specs/kubernetes-mapping.md)) |
| `policy/`, `.github/` | The ground rules as Rego policies; the CI workflow and Dependabot ([pipeline spec](docs/specs/pipeline.md)) |
| `tools/` | Repo checks, git hooks and the operations script [tools/obs.sh](tools/obs.sh) |
| [method/](method/README.md) | The shared method |

## Checks

```bash
git config core.hooksPath tools/hooks   # once per clone
python3 tools/check-docs.py             # links, anchors, em dashes, secrets, Azure ids, addresses
bash tools/ci-tools.sh && bash tools/ci.sh   # every CI step on the laptop (docs/runbooks/pipeline.md)
bash tools/obs.sh drift                 # code vs Azure at a session start: 0 match, 2 drift, 1 error
```
