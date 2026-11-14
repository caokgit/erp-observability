#!/usr/bin/env bash
# Keep the shared method in step between a sibling repo and its source, the lab (docs/specs/method.md in the lab).
#
#   bash tools/sync-method.sh [pull] [source]          # take the source's method (default source ~/lab)
#   bash tools/sync-method.sh push "<what changed>"    # send this repo's method edits to the source, commit them there
#
# pull: copies every file in the source's method/MANIFEST from the source's last commit, keeps the executable bit,
#       writes method/VERSION. Refuses when a MANIFEST file is uncommitted in the source, or edited here and not pushed.
# push: copies the method files edited here (their sha256 differs from method/VERSION) into the source, runs the
#       source's check, commits there naming this repo, then pulls. Refuses when the source changed one of the same
#       files since the last sync (merge that file by hand), or when the source's check fails.
# Never touches tools/repo.toml or AGENTS.md.
set -euo pipefail

ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
VERSION="$ROOT/method/VERSION"
MODE=pull
if [[ "${1:-}" == pull || "${1:-}" == push ]]; then MODE=$1; shift; fi

source_from_version() {
  local s
  s=$(sed -n 's/^source //p' "$VERSION" 2>/dev/null | head -1)
  echo "${s/#\~/$HOME}"
}

# Files edited here since the last sync: "path" per line (a file listed in VERSION whose sha256 differs, or a file in
# the local MANIFEST that VERSION does not list yet).
edited_here() {
  [[ -f "$VERSION" ]] || return 0
  local digest path
  while read -r digest path; do
    if [[ ! -f "$ROOT/$path" ]] || [[ "$(sha256sum "$ROOT/$path" | cut -d' ' -f1)" != "$digest" ]]; then echo "$path"; fi
  done < <(grep -E '^[0-9a-f]{64}  ' "$VERSION")
  if [[ -f "$ROOT/method/MANIFEST" ]]; then
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$ROOT/method/MANIFEST" | while read -r path; do
      grep -qE "^[0-9a-f]{64}  $path\$" "$VERSION" || echo "$path"
    done
  fi
}

do_pull() {
  local src=$1 f mode commit dirty edited="" path
  # an edited file that already equals the source's last commit is not an edit (a half-finished pull, a copied script)
  while read -r path; do
    [[ -n "$path" ]] || continue
    if ! git -C "$src" cat-file -e "HEAD:$path" 2>/dev/null \
       || [[ "$(git -C "$src" show "HEAD:$path" | sha256sum | cut -d' ' -f1)" != "$(sha256sum "$ROOT/$path" 2>/dev/null | cut -d' ' -f1)" ]]; then
      edited+="$path"$'\n'
    fi
  done < <(edited_here | sort -u)
  if [[ -n "$edited" ]]; then
    printf 'method files edited here and not pushed; run tools/sync-method.sh push "<what changed>" first:\n%s\n' "$edited" >&2
    exit 1
  fi
  mapfile -t FILES < <(git -C "$src" show HEAD:method/MANIFEST | sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d')
  dirty=$(git -C "$src" status --porcelain -- "${FILES[@]}")
  if [[ -n "$dirty" ]]; then
    printf 'uncommitted method files in the source; commit them first:\n%s\n' "$dirty" >&2
    exit 1
  fi
  commit=$(git -C "$src" rev-parse HEAD)
  mkdir -p "$ROOT/method"
  {
    echo "source ${src/#$HOME/\~}"
    echo "commit $commit"
    echo "date $(date +%Y-%m-%d)"
  } > "$VERSION.new"
  for f in "${FILES[@]}"; do
    mkdir -p "$ROOT/$(dirname "$f")"
    git -C "$src" show "HEAD:$f" > "$ROOT/$f"
    mode=$(git -C "$src" ls-files -s -- "$f" | cut -d' ' -f1)
    if [[ "$mode" == 100755 ]]; then chmod +x "$ROOT/$f"; else chmod -x "$ROOT/$f"; fi
    echo "$(sha256sum "$ROOT/$f" | cut -d' ' -f1)  $f" >> "$VERSION.new"
  done
  mv "$VERSION.new" "$VERSION"
  echo "pulled ${#FILES[@]} files from ${src/#$HOME/\~} at ${commit:0:7}"
  git -C "$ROOT" status --short -- method tools
}

do_push() {
  local src=$1 subject=$2 path base_digest src_digest conflicts="" repo
  [[ -f "$VERSION" ]] || { echo "no method/VERSION: pull once before pushing" >&2; exit 1; }
  mapfile -t EDITED < <(edited_here | sort -u)
  if [[ ${#EDITED[@]} -eq 0 ]]; then echo "nothing edited here since the last sync"; return 0; fi
  if [[ -n "$(git -C "$src" status --porcelain -- "${EDITED[@]}")" ]]; then
    echo "uncommitted changes to the same files in the source; commit or discard them there first" >&2
    exit 1
  fi
  for path in "${EDITED[@]}"; do
    base_digest=$(grep -E "^[0-9a-f]{64}  $path\$" "$VERSION" | cut -d' ' -f1 || true)
    # a file new in this push is not in the source yet: `git show` would fail the pipe under pipefail (2026-11-08)
    src_digest=""
    if git -C "$src" cat-file -e "HEAD:$path" 2>/dev/null; then
      src_digest=$(git -C "$src" show "HEAD:$path" | sha256sum | cut -d' ' -f1)
    fi
    if [[ "$src_digest" != "$base_digest" ]]; then conflicts+="$path"$'\n'; fi
  done
  if [[ -n "$conflicts" ]]; then
    printf 'the source changed these files since the last sync; merge each by hand into the source, then pull:\n%s' "$conflicts" >&2
    exit 1
  fi
  for path in "${EDITED[@]}"; do
    mkdir -p "$src/$(dirname "$path")"
    cp "$ROOT/$path" "$src/$path"
    if [[ -x "$ROOT/$path" ]]; then chmod +x "$src/$path"; fi
  done
  local out; out=$(mktemp)
  if ! (cd "$src" && python3 tools/check-docs.py > "$out" 2>&1); then
    cat "$out" >&2; rm -f "$out"
    git -C "$src" checkout -q -- "${EDITED[@]}" 2>/dev/null || true
    echo "the source's check failed; nothing committed there, your edits are kept here" >&2
    exit 1
  fi
  rm -f "$out"
  repo=$(basename "$ROOT")
  git -C "$src" add -- "${EDITED[@]}"
  git -C "$src" commit -q -m "method: $subject (from $repo)" -m "Spec: docs/specs/method.md#changing-the-method" -- "${EDITED[@]}"
  echo "pushed ${#EDITED[@]} file(s) to ${src/#$HOME/\~} as $(git -C "$src" rev-parse --short HEAD): ${EDITED[*]}"
  do_pull "$src"
}

main() {
  if [[ "$MODE" == push ]]; then
    [[ -n "${1:-}" ]] || { echo 'usage: bash tools/sync-method.sh push "<what changed>"' >&2; exit 1; }
    SRC=$(source_from_version)
    [[ -n "$SRC" ]] || SRC="$HOME/lab"
    SRC=$(git -C "$SRC" rev-parse --show-toplevel)
    [[ "$SRC" != "$ROOT" ]] || { echo "this is the source repo: commit method changes here directly" >&2; exit 1; }
    do_push "$SRC" "$1"
  else
    SRC=$(git -C "${1:-$HOME/lab}" rev-parse --show-toplevel)
    [[ "$SRC" != "$ROOT" ]] || { echo "this is the source repo; edit method/ here and pull in each sibling" >&2; exit 1; }
    do_pull "$SRC"
  fi
}

# One line, so bash has read the whole script before a pull overwrites this file
main "$@"; exit $?
