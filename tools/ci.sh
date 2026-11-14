#!/usr/bin/env bash
# The pipeline's checks (docs/specs/pipeline.md#the-workflow): the same script in GitHub Actions and on the laptop.
# Offline: it reads the repo only and never reaches Azure or the client's Postgres (the step sql runs its own container). Every step runs; the summary lists each one,
# and the exit code is 1 if any failed.
#
#   bash tools/ci-tools.sh && bash tools/ci.sh          all steps
#   bash tools/ci.sh fmt policy                          only the steps named
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); cd "$REPO"
export PATH=$REPO/.scratch_tf/bin:$PATH
export TF_PLUGIN_CACHE_DIR=${TF_PLUGIN_CACHE_DIR:-$REPO/.scratch_tf/plugin-cache} TF_IN_AUTOMATION=1
mkdir -p "$TF_PLUGIN_CACHE_DIR"
ROOTS=(terraform/envs/shared terraform/envs/dev terraform/envs/stg)
MODULES=(terraform/modules/alerts terraform/modules/sql-job)

step_fmt() { terraform fmt -check -recursive -diff terraform; }

step_validate() {  # each root and module on its own, no backend: nothing reaches Azure
  local d rc=0 had
  for d in "${ROOTS[@]}" "${MODULES[@]}"; do
    echo "-- $d"
    [ -e "$d/.terraform.lock.hcl" ] && had=1 || had=0
    TF_DATA_DIR=$REPO/.scratch_tf/ci/${d//\//_} terraform -chdir="$d" init -backend=false -input=false -no-color >/dev/null \
      && TF_DATA_DIR=$REPO/.scratch_tf/ci/${d//\//_} terraform -chdir="$d" validate -no-color || rc=1
    [ $had -eq 1 ] || rm -f "$d/.terraform.lock.hcl"  # a module keeps no lock file: its roots' locks pin the providers
  done
  return $rc
}

step_tflint() { tflint --recursive --chdir=terraform --config="$REPO/terraform/.tflint.hcl" --no-color; }

step_trivy_config() {  # misconfigurations in the Terraform, HIGH and CRITICAL fail
  trivy config --quiet --exit-code 1 --severity HIGH,CRITICAL terraform
}

step_trivy_deps() {  # known vulnerabilities in the job's pinned Python packages, HIGH and CRITICAL fail
  trivy fs --quiet --scanners vuln --exit-code 1 --severity HIGH,CRITICAL job
}

step_bandit() {  # SAST on the track's Python: MEDIUM severity and confidence or above fail; B104 skipped (no server here)
  bandit -q -r job kql sql tools terraform/aws/cost --severity-level medium --confidence-level medium -s B104
}

step_unit() { python3 -m unittest discover -s job -p 'test_*.py'; }  # the log reader's counting (round 5, G7), the job's rows

# The SQL job's queries on a throwaway PostgreSQL 17 (round 7, N2): trust auth inside the container, no port published,
# removed at the end. The image is pinned by digest (postgres:17, pulled 2026-11-14).
PG_IMAGE=postgres:17@sha256:ff87138949ad9a46f32ff23bd6852b52ce024a13dffe9b4087be98292cdd3b4f
step_sql() {
  local c=obs-ci-pg-$$ rc=1 i
  docker run -d --rm --name "$c" -e POSTGRES_HOST_AUTH_METHOD=trust "$PG_IMAGE" >/dev/null || return 1
  for i in $(seq 1 60); do  # TCP answers only after the image's init, when the real server has started
    docker exec "$c" pg_isready -q -h 127.0.0.1 -U postgres && { rc=0; break; }
    sleep 1
  done
  [ $rc -eq 0 ] && { OBS_TEST_PG_CONTAINER=$c python3 -m unittest discover -s job -p 'test_sql_job.py' -v || rc=1; }
  docker rm -f -v "$c" >/dev/null 2>&1  # -v: the image's data volume too, or each run leaves one
  return $rc
}

step_promtool() {  # the Kubernetes mapping's PromQL rules: valid, and each fires on its test shape (K2)
  (cd k8s/rules && promtool check rules erp.rules.yaml && promtool test rules erp.rules.test.yaml)
}

step_gitleaks() {  # every commit of the history (CI checks out the full history)
  gitleaks git --no-banner --redact .
}

step_docs() { python3 tools/check-docs.py; }

step_policy() { bash tools/policy.sh && opa check --strict policy && opa fmt --fail --list policy >/dev/null; }

step_repo_trace() {  # what reaches Azure from the repo's text: the rendered queries, the JSON the roots read
  local rule env rc=0 n=0
  for rule in $(python3 -c "import json;print(' '.join(json.load(open('kql/rules.json'))['rules']))"); do
    for env in $(python3 -c "import json,sys;print(' '.join(json.load(open('kql/rules.json'))['rules'][sys.argv[1]].get('envs',['dev','stg'])))" "$rule"); do
      python3 kql/backtest.py "$rule" --env "$env" --print > "$REPO/.scratch_tf/query.kql" || { echo "render failed: $rule $env"; rc=1; continue; }
      python3 tools/no-repo-trace.py < "$REPO/.scratch_tf/query.kql" > /dev/null || { echo "trace in $rule ($env)"; rc=1; }
      n=$((n + 1))
    done
  done
  echo "$n rendered queries scanned"
  for f in $(find terraform -name '*.json' -not -path '*/.terraform/*' | sort); do
    python3 tools/no-repo-trace.py < "$f" | sed "s#^#$f: #" | tail -1
    python3 tools/no-repo-trace.py < "$f" > /dev/null || rc=1
  done
  rm -f "$REPO/.scratch_tf/query.kql"
  return $rc
}

step_aws_test() {  # the AWS design's guardrails (terraform/aws, D20): never applied, tested on a mock provider
  local d=terraform/aws/modules/scp rc=0
  TF_DATA_DIR=$REPO/.scratch_tf/ci/aws_scp terraform -chdir="$d" init -backend=false -input=false -no-color >/dev/null \
    && TF_DATA_DIR=$REPO/.scratch_tf/ci/aws_scp terraform -chdir="$d" test -no-color || rc=1
  rm -f "$d/.terraform.lock.hcl"
  return $rc
}

ALL=(fmt validate tflint trivy_config trivy_deps bandit unit sql promtool gitleaks docs policy aws_test repo_trace)
[ $# -gt 0 ] && STEPS=("$@") || STEPS=("${ALL[@]}")
declare -A RESULT; failed=0
for s in "${STEPS[@]}"; do
  echo "::group::$s"
  if "step_$s"; then RESULT[$s]=pass; else RESULT[$s]=FAIL; failed=1; fi
  echo "::endgroup::"
done
echo "== summary"
for s in "${STEPS[@]}"; do printf '%-13s %s\n' "$s" "${RESULT[$s]}"; done
exit $failed
