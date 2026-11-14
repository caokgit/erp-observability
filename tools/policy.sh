#!/usr/bin/env bash
# The track's ground rules as code (policy/terraform/, docs/specs/pipeline.md#the-policies), run by CI and by hand:
#
#   bash tools/policy.sh            the policies' own tests, then every .tf file applied to Azure: terraform/envs and
#                                   terraform/modules (package hcl); terraform/aws is a paper design, never applied (D20)
#   bash tools/policy.sh plan       a saved plan's JSON on stdin (package plan); obs.sh plan pipes into it
#
# conftest comes from PATH, else from .scratch_tf/bin (gitignored; docs/runbooks/pipeline.md#tools).
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
PATH=$PATH:$REPO/.scratch_tf/bin
cd "$REPO"
case "${1:-source}" in
source)
  conftest verify --no-color -p policy
  mapfile -t files < <(find terraform/envs terraform/modules -name '*.tf' -not -path '*/.terraform/*' | sort)
  conftest test --no-color --namespace hcl -p policy "${files[@]}" ;;
plan)
  conftest test --no-color --namespace plan -p policy --parser json - ;;
*) sed -n '2,7p' "$0"; exit 2 ;;
esac
