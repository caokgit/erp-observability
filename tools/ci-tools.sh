#!/usr/bin/env bash
# Install the pipeline's tools into .scratch_tf/bin (gitignored), the same versions in CI and on the laptop
# (docs/specs/pipeline.md#the-workflow). Each download is checked against the SHA-256 pinned here, taken from the
# release's own checksum file on 2026-11-08: a release replaced after that date fails the check. A version bump changes
# the version and its sum together.
#
#   bash tools/ci-tools.sh          install what is missing, then print the versions
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
BIN=$REPO/.scratch_tf/bin; DL=$REPO/.scratch_tf/dl
mkdir -p "$BIN" "$DL"
GH=https://github.com

# name | version | url | sha256 | how to unpack
TOOLS=(
  "terraform|1.17.1|https://releases.hashicorp.com/terraform/1.17.1/terraform_1.17.1_linux_amd64.zip|4638628058e71a55212b1c563712eac03b902128f40740f3dc8174df12135061|zip"
  "tflint|0.65.0|$GH/terraform-linters/tflint/releases/download/v0.65.0/tflint_linux_amd64.zip|d4c545ed2e29d6338604b586f34f544f380f70f243aa72f7b484713835eaec61|zip"
  "trivy|0.76.1|$GH/aquasecurity/trivy/releases/download/v0.76.1/trivy_0.76.1_Linux-64bit.tar.gz|c7cbe3137fb8a48a17574bede3dd6beb16742d1e9772929940fc90082c39d9c0|tgz"
  "gitleaks|8.30.1|$GH/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz|551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb|tgz"
  "conftest|0.71.1|$GH/open-policy-agent/conftest/releases/download/v0.71.1/conftest_0.71.1_Linux_x86_64.tar.gz|c3f6b2a753bd56e377a1e51a95ae3e057f926f2e9139f7d5b5dfbbaf810f7985|tgz"
  "promtool|3.15.1|$GH/prometheus/prometheus/releases/download/v3.15.1/prometheus-3.15.1.linux-amd64.tar.gz|6a726885328ad9efebbf36e876ce2fb6225468a71fd1e7ce3ba666d5f4d97a84|tgz1"
  "opa|1.21.3|$GH/open-policy-agent/opa/releases/download/v1.21.3/opa_linux_amd64_static|add7c9dcf56e1ce1538426a6ee595ea1cc7ee830bbedd4c23219825b02b19a79|bin"
)

for t in "${TOOLS[@]}"; do
  IFS='|' read -r name version url sum kind <<< "$t"
  stamp=$BIN/.$name-$version
  [ -x "$BIN/$name" ] && [ -e "$stamp" ] && continue
  file=$DL/$(basename "$url")
  curl -sSfL -o "$file" "$url"
  echo "$sum  $file" | sha256sum -c --quiet || { rm -f "$file"; echo "checksum mismatch: $name $version" >&2; exit 1; }
  case $kind in
    zip) python3 -c "import sys,zipfile;zipfile.ZipFile(sys.argv[1]).extract(sys.argv[2],sys.argv[3])" "$file" "$name" "$BIN" ;;
    tgz) tar -xzf "$file" -C "$BIN" "$name" ;;
    tgz1) tar -xzf "$file" -C "$BIN" --strip-components=1 --wildcards "*/$name" ;;   # one folder down
    bin) cp "$file" "$BIN/$name" ;;
  esac
  chmod 755 "$BIN/$name"; rm -f "$BIN/.$name-"*; touch "$stamp"
done
# The Python tools (bandit): a venv from tools/ci-requirements.txt, every wheel checked against its pinned SHA-256
PY=$REPO/.scratch_tf/py
if [ ! -x "$PY/bin/bandit" ] || ! cmp -s "$REPO/tools/ci-requirements.txt" "$PY/.requirements"; then
  rm -rf "$PY"; python3 -m venv "$PY"
  "$PY/bin/pip" install -q --disable-pip-version-check --require-hashes --only-binary=:all: -r "$REPO/tools/ci-requirements.txt"
  cp "$REPO/tools/ci-requirements.txt" "$PY/.requirements"
fi
ln -sf "$PY/bin/bandit" "$BIN/bandit"
# sed reads its whole input (head would close the pipe early, and pipefail would fail on SIGPIPE)
"$BIN/terraform" version | sed -n 1p; "$BIN/tflint" --version 2>&1 | sed -n '/TFLint version/p'
"$BIN/trivy" --version | sed -n '1s/^/trivy /p'; "$BIN/gitleaks" version | sed 's/^/gitleaks /'
"$BIN/conftest" --version | sed -n 1p; "$BIN/opa" version | sed -n '1s/^/opa /p'
"$BIN/bandit" --version | sed -n 1p; "$BIN/promtool" --version 2>&1 | sed -n '1s/^promtool, //p'
