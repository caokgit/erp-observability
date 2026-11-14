# DevSecOps: scanning the client's ERP code and images

Stage D of the plan of 2026-11-08 ([roadmap](../design.md#roadmap), [D25](../design.md#decisions)): SAST, SCA, secret and
configuration scans of the client's own ERP source, image scans of the images stg runs, findings for the ERP team, and SAST
added to this repo's own CI. Status: built and run on
2026-11-08; everything here is read only.

## Scope

**One idea: read what the ERP team builds and runs, with the same pinned tools every time, rank the findings by where
they sit and whether a fix exists, and hand the short list to the team that owns the code; change nothing of theirs.**

| Target | What | How it is read |
|---|---|---|
| The ERP source | The ERP repo, branch `develop`, at a recorded commit, cloned read only beside this repo (push disabled) | In place; nothing copied into this repo ([D14](../design.md#decisions) not needed: no simulation) |
| stg's images | The Odoo image both stg apps run and their two nginx sidecars, by the tags the apps run | `trivy image --image-src remote` with a registry token from the read login, passed in the environment, never printed; no pull to Docker |
| This repo | Its Python (`job/`, `kql/`, `sql/`, `tools/`, `terraform/aws/cost/`) | bandit in CI, beside the S2 steps |

Out of scope: DAST (it attacks a running system; the ground rules allow reads only), the prd Odoo (stopped), dev's
image beyond its tag (dev is the rehearsal ground, not the risk).

## The scans

| Scan | Tool and version | On | Output |
|---|---|---|---|
| Image | Trivy 0.76.1 (the lab's toolchain), scanners `vuln,secret` | stg's Odoo image and nginx sidecars | JSON per image |
| SCA | `trivy fs --scanners vuln` | The source | JSON |
| Configuration | `trivy config` | The source's Dockerfiles | JSON |
| SAST | bandit 1.8.6; semgrep 1.142.0 with `p/python` (and pydantic 2.11.9, which semgrep 1.142.0 needs) | The custom add-ons, tests and `node_modules` excluded | JSON |
| Secrets | gitleaks 8.30.1, `--redact` | The source's files and its history | JSON with no value |

[tools/devsecops.sh](../../tools/devsecops.sh) runs each as one subcommand into the gitignored `.scratch_sec/`, and
`summary` prints the counts the findings page and this spec use. The tools for the source scans live in a venv in
`.scratch_sec/` pinned by version; CI's bandit is pinned by hash.

**Ranking.** A finding is acted on first when it is HIGH or Critical **and** has a fix, or when it touches a signal the
track watches (a call without a timeout holds a worker until its time limit kills it (the rule O1); a credential in a log line reaches the
workspace). Counts are reported with their concentration: the package or rule that holds most of them.

## The findings and where they go

The findings with files, lines, packages and CVEs go to the ERP team in a findings page
that is never published. This repo changes none of their code, image or pipeline.

**The public view is counts only**: by
tool, severity and class, never a file, line, module, package version or CVE of the client's code. The concept page
with package-level examples, the scans' runbook and the findings page are not published.

**REAL, 2026-11-08**, counts by tool, severity and class (the versions, packages, files and CVEs are in the findings):

| Scan | Result |
|---|---|
| Image, the Odoo image | 3,789 OS findings (15 Critical, 377 HIGH); 85 % of them and every Critical in one package the runtime does not need (a build dependency); 3 HIGH OS CVEs with a fix, and 4 HIGH in language packages, all with a fix |
| Image, the nginx sidecars | 3 Critical and 64 HIGH each; 51 HIGH or Critical CVEs with a fixed package |
| SCA | 146 findings in two front-end lockfiles (8 Critical); 9 of 11 Python requirement lines unpinned, so not checkable |
| Configuration | 3 HIGH, 1 MEDIUM, 4 LOW |
| SAST | bandit 337 over 96,625 lines (5 HIGH, 187 MEDIUM; 170 of them SQL built from strings; 8 HTTP calls without a timeout); semgrep 13 (6 possible credentials in logs, 3 unsafe XML parses) |
| Secrets | 1 key-shaped string, a false positive inside a vendored, minified library |

## This repo's CI

`tools/ci.sh` gains a step `bandit`: bandit on the track's Python at MEDIUM severity and confidence or above, fails
the run on any finding. Two findings are answered in the code (`# nosec` with the reason: the cost estimate's
`urlopen` reads fixed `https` price-list URLs); `B104` (binding to all interfaces) is skipped for the repo, which runs
no server (it matched the mask tool's own address pattern). `tools/ci-tools.sh` installs bandit into a venv from
[tools/ci-requirements.txt](../../tools/ci-requirements.txt), every wheel pinned by SHA-256.

## Mask words

The image listing showed dev's registry name: the mask words held only stg's.
`terraform/names.sh` adds the first label of every registry the Odoo apps' images name.

## Acceptance

| # | Check | How |
|---|---|---|
| DS1 | Learn page and this spec | Written with the scans' real values |
| DS2 | Images scanned | stg's Odoo image and both sidecars, read only; summary by severity, fixability and concentration |
| DS3 | Source scanned | SCA, configuration, SAST (two tools), secrets, at a recorded commit, in place |
| DS4 | Findings for the ERP team | A ranked list: what to do first, with the evidence |
| DS5 | SAST in this repo's CI | `bandit` step green on the laptop and on GitHub; pinned by hash |
| DS6 | Mask words | `names.sh` writes every app image's registry; the image listing shows no registry name |
| DS7 | Public | The export carries counts only; its search passes |

## Teardown

Nothing in Azure or on a server. Local only: `.scratch_sec/` (reports, the venv, Trivy's cache), deleted with
`rm -rf .scratch_sec`.
