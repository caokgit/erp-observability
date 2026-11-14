# method/

The shared working method of the owner's repos: [METHOD.md](METHOD.md) (the rules every repo's `AGENTS.md` imports),
[templates/](templates/journal-entry.md) (journal entry, runbook page, learn section, review, post-mortem), and the shared tools
listed in [MANIFEST](MANIFEST).

| | In the lab (the source) | In a sibling |
|---|---|---|
| These files | Edited here, then committed | Edited here too, then sent to the lab with `bash tools/sync-method.sh push "<what changed>"` |
| `method/VERSION` | Absent | Written by the sync: source commit, date, sha256 of each file |
| Own settings | `tools/repo.toml`, `AGENTS.md` | `tools/repo.toml`, `AGENTS.md` |

To change the method: edit it in the repo you work in and run `python3 tools/check-docs.py`. In the lab, commit; in a
sibling, run `bash tools/sync-method.sh push "<what changed>"` (it commits in the lab and updates the copy), then commit
the copy. Every other sibling runs `bash tools/sync-method.sh` (pull) in its next session; its check warns until it does.

A new sibling's first sync: copy the script once (`cp ~/lab/tools/sync-method.sh tools/`), write its
`tools/repo.toml`, then run `bash tools/sync-method.sh`; the script finds the repo to update from its own location,
so run from the lab it refuses.
