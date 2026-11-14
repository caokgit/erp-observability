#!/usr/bin/env bash
# Does a change touch a path this CI job checks? (docs/specs/pipeline.md#the-workflow; the idea from the lab's CI)
#   tools/ci-paths.sh <terraform|python|kubernetes> [<git range>]   prints one line ending in run=true or run=false
# In a pull_request run, HEAD is GitHub's test merge commit, so HEAD^1..HEAD (the default) is what the pull request
# brings in; a push run passes <before>..<after>, which needs the full history (fetch-depth 0).
# When the range cannot be read, the answer is run=true: a publish to the public repo force-pushes one amended commit,
# whose "before" is no longer in the history, and a new branch's "before" is all zeros; a doubt never becomes a skip.
# python also watches kql/ (backtest.py is Python, and bandit scans it) and terraform/aws/cost/ (the AWS estimate's
# scripts). In Actions the answer also goes to $GITHUB_OUTPUT for the job's later steps.
set -euo pipefail
job=${1:?usage: tools/ci-paths.sh <terraform|python|kubernetes> [<git range>]}
range=${2:-HEAD^1..HEAD}
always='^(\.github/workflows/ci\.yml|tools/(ci-paths\.sh|ci\.sh|ci-tools\.sh|ci-requirements\.txt))$'  # every job runs
case $job in
  terraform)  paths='^(terraform/|policy/|kql/|tools/(policy\.sh|no-repo-trace\.py)$)' ;;
  python)     paths='^(job/|kql/|sql/|tools/[^/]+\.py$|terraform/aws/cost/)' ;;
  kubernetes) paths='^k8s/rules/' ;;
  *) echo "ci-paths: unknown job '$job'" >&2; exit 2 ;;
esac
if files=$(git diff --name-only "$range" 2>/dev/null); then
  hits=$(grep -E -e "$always" -e "$paths" <<<"$files" || true)
  if [[ -n $hits ]]; then run=true; else run=false; fi
  echo "$job: $(grep -c . <<<"$files" || true) files changed, $(grep -c . <<<"$hits" || true) checked by this job: run=$run"
else
  run=true
  echo "$job: the range $range cannot be read (a force-push, or a new branch): run=$run"
fi
[[ -z ${GITHUB_OUTPUT:-} ]] || echo "run=$run" >> "$GITHUB_OUTPUT"
