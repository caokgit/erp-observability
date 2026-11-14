#!/usr/bin/env bash
# Read-only security scans of the client's ERP source and of the images stg runs (docs/specs/devsecops.md). Reports go to the
# gitignored .scratch_sec/; only counts are printed, and what may hold a name goes through tools/mask.py.
#
#   bash tools/devsecops.sh setup              the venv with the pinned SAST tools (.scratch_sec/venv)
#   bash tools/devsecops.sh images             trivy on every image the stg Odoo apps run (remote, the read login's token)
#   bash tools/devsecops.sh source [path]      SCA, configuration, SAST (bandit, semgrep), secrets on the source, in place
#   bash tools/devsecops.sh summary            the counts the spec and the findings page use
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); cd "$REPO"
TOOLCHAIN=$HOME/lab/.toolchain/bin
OUT=$REPO/.scratch_sec; VENV=$OUT/venv
SRC_DEFAULT=$HOME/erp-source
export TRIVY_CACHE_DIR=$OUT/trivy-cache AZURE_CONFIG_DIR=$HOME/lab/.scratch_az
mkdir -p "$OUT"; chmod 700 "$OUT"
mask() { python3 "$REPO/tools/mask.py"; }

setup() {
  [[ -x $VENV/bin/bandit && -x $VENV/bin/semgrep ]] && { echo "venv ready"; return; }
  python3 -m venv "$VENV"
  "$VENV/bin/pip" -q install bandit==1.8.6 semgrep==1.142.0 pydantic==2.11.9   # semgrep 1.142.0 fails to import on newer pydantic
  echo "venv ready: $("$VENV/bin/bandit" --version | sed -n 1p), semgrep $("$VENV/bin/semgrep" --version)"
}

images() {  # the tags the stg apps run now, each image once
  local reg sub refs ref token
  reg=$(python3 -c "import json;print(json.load(open('terraform/envs/shared/names.auto.tfvars.json'))['registry']['name'])")
  sub=$(python3 -c "import json;print(json.load(open('terraform/envs/stg/names.auto.tfvars.json'))['subscription_ids']['stg'])")
  refs=$(python3 -c "import json;[print(a['resource_group'], a['name']) for a in json.load(open('terraform/envs/stg/names.auto.tfvars.json'))['apps']]" \
    | while read -r rg app; do az containerapp show --subscription "$sub" -g "$rg" -n "$app" \
        --query "properties.template.containers[].image" -o tsv; done | sort -u)
  local login user token
  login=$(az acr login -n "$reg" --expose-token -o json 2>/dev/null)   # the token's user is a fixed placeholder name
  user=$(python3 -c "import json,sys;print(json.load(sys.stdin)['username'])" <<< "$login")
  token=$(python3 -c "import json,sys;print(json.load(sys.stdin)['accessToken'])" <<< "$login"); unset login
  for ref in $refs; do
    local name=${ref#*/}; local file=$OUT/image-$(echo "$name" | tr '/:' '__').json
    TRIVY_USERNAME=$user TRIVY_PASSWORD=$token \
      "$TOOLCHAIN/trivy" image --quiet --image-src remote --scanners vuln,secret --format json --output "$file" "$ref"
    echo "image $name -> ${file#$REPO/}"
  done 2>&1 | mask
}

source_() {
  local src=${1:-$SRC_DEFAULT}
  [[ -d $src/.git ]] || { echo "no git checkout at $src" >&2; exit 2; }
  echo "source at $(git -C "$src" rev-parse --short HEAD) ($(git -C "$src" log -1 --format=%cs)), $(git -C "$src" status --porcelain | wc -l) local changes"
  "$TOOLCHAIN/trivy" fs --quiet --scanners vuln --format json --output "$OUT/src-sca.json" "$src"
  "$TOOLCHAIN/trivy" config --quiet --format json --output "$OUT/src-config.json" "$src"
  "$VENV/bin/bandit" -q -r "$src/custom-addons" -x '*/tests/*,*/node_modules/*' -f json -o "$OUT/src-bandit.json" || true
  "$VENV/bin/semgrep" scan --quiet --metrics off --config p/python --exclude node_modules --exclude tests --json \
    --output "$OUT/src-semgrep.json" "$src/custom-addons" > /dev/null 2>&1
  "$TOOLCHAIN/gitleaks" dir --no-banner --redact --report-format json --report-path "$OUT/src-gitleaks-dir.json" "$src" > /dev/null 2>&1 || true
  "$TOOLCHAIN/gitleaks" git --no-banner --redact --report-format json --report-path "$OUT/src-gitleaks-git.json" "$src" > /dev/null 2>&1 || true
  echo "reports in .scratch_sec/: src-sca, src-config, src-bandit, src-semgrep, src-gitleaks-{dir,git}"
}

summary() {
  python3 -I - "$OUT" <<'PY'
import collections, glob, json, os, sys
out = sys.argv[1]
C = collections.Counter
def load(n):
    p = os.path.join(out, n)
    return json.load(open(p)) if os.path.exists(p) else None
for f in sorted(glob.glob(os.path.join(out, "image-*.json"))):
    d = json.load(open(f)); vs = [(r["Class"], x) for r in d.get("Results", []) for x in r.get("Vulnerabilities") or []]
    osv = [x for c, x in vs if c == "os-pkgs"]
    top = C(x["PkgName"] for x in osv).most_common(1)
    hc_fix = {x["VulnerabilityID"] for _, x in vs if x["Severity"] in ("HIGH", "CRITICAL") and x.get("FixedVersion")}
    print(f'{os.path.basename(f)}: {d["Metadata"]["OS"]["Family"]} {d["Metadata"]["OS"]["Name"]}'
          f'{" (end of life)" if d["Metadata"]["OS"].get("EOSL") else ""}; {len(vs)} findings {dict(C(x["Severity"] for _, x in vs))};'
          f' top package {top[0][1] if top else 0} of {len(osv)} OS findings; HIGH or CRITICAL with a fix: {len(hc_fix)}')
s = load("src-sca.json")
if s:
    for r in s.get("Results", []):
        v = r.get("Vulnerabilities") or []
        if v: print(f'sca {r["Type"]}: {len(v)} {dict(C(x["Severity"] for x in v))}')
c = load("src-config.json")
if c:
    m = [x for r in c.get("Results", []) for x in r.get("Misconfigurations") or []]
    print("config:", dict(C(x["ID"] + " " + x["Severity"] for x in m)))
b = load("src-bandit.json")
if b:
    r = b["results"]
    print(f'bandit: {b["metrics"]["_totals"]["loc"]} lines, {len(r)} findings {dict(C(x["issue_severity"] for x in r))};',
          "top", C(x["test_id"] for x in r).most_common(4))
g = load("src-semgrep.json")
if g:
    print(f'semgrep: {len(g["results"])} findings', dict(C(x["check_id"].split(".")[-1] for x in g["results"])))
for k in ("dir", "git"):
    l = load(f"src-gitleaks-{k}.json")
    if l is not None: print(f"gitleaks {k}: {len(l)}", dict(C(x["RuleID"] for x in l)))
PY
}

case "${1:-}" in
  setup) setup ;; images) images ;; source) source_ "${2:-}" ;; summary) summary ;;
  *) echo "usage: $0 setup|images|source [path]|summary" >&2; exit 2 ;;
esac
