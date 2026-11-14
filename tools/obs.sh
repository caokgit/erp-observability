#!/usr/bin/env bash
# The track's live operations, one subcommand each (docs/runbooks/deploy.md). Logins per AGENTS.md: az to create
# resources with .scratch_az_write, reads with .scratch_az; psql through the lab's service file. Names come from
# terraform/envs/<env>/names.auto.tfvars.json; secrets are read into variables and never printed; output goes
# through tools/mask.py.
#
#   bash tools/obs.sh tf <root> <terraform args...>     terraform in terraform/envs/<root>, the write login
#   bash tools/obs.sh plan <root>                       plan to .scratch_tf/<root>/<root>.tfplan, then the repo-trace scan
#                                                       and the policies (tools/policy.sh plan); a refused plan is deleted
#   bash tools/obs.sh drift                             plan shared, dev and stg without a lock or a plan file: exit 0
#                                                       when code and Azure match, 2 when a root differs, 1 on an error
#   bash tools/obs.sh apply <root>                      apply that saved plan
#   bash tools/obs.sh role <env> <admin service>        sql/obs_monitor.sql as the server's admin (the verifier only)
#   bash tools/obs.sh role-check <env> <admin service>  acceptance A1 as obs_monitor, then the grants and grantors
#   bash tools/obs.sh push <tag>                        build job/ and push obs/sql-job:<tag> to the stg registry
#   bash tools/obs.sh ag-test <env> <page|ticket>       Azure's test alert through that action group
#   bash tools/obs.sh job <env> start|list [log]        start a run of the SQL job (or the log reader), or list its runs
#   bash tools/obs.sh kq '<KQL>' [ISO duration]          a query on the platform workspace (default PT2H)
#   bash tools/obs.sh kq-env <env> '<KQL>' [duration]   the same, after the environment's targets as let statements
#                                                       (Apps, Web, Cron, Servers, Gateway, role()): no name in the KQL
#   bash tools/obs.sh trace-live                        every resource tagged owner=observability-track, scanned
#   bash tools/obs.sh audit                             every place the track wrote, scanned for the repo: resources'
#                                                       full bodies, role assignments, state blobs, the image's
#                                                       manifests, the workspace's rows, the Activity Log;
#                                                       and the application names our sessions left in Postgres logs
#   bash tools/obs.sh inventory                         what the track has in Azure: resources, role assignments,
#                                                       tables, the image repository (the spec's teardown inventory)
#   bash tools/obs.sh drill-lock <reader service> <s>   L1's drill: a read-only session holds an advisory lock <s>
#                                                       seconds while a second waits for it; no data is touched
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
TOOLCHAIN=$HOME/lab/.toolchain/bin
AZ_WRITE=$HOME/lab/.scratch_az_write
AZ_READ=$HOME/lab/.scratch_az
export PGSERVICEFILE=$HOME/lab/.scratch_pg/pg_service.conf PGPASSFILE=$HOME/lab/.scratch_pg/pgpass
export PATH=$TOOLCHAIN:$PATH TF_PLUGIN_CACHE_DIR=$REPO/.scratch_tf/plugin-cache
mask() { python3 "$REPO/tools/mask.py"; }
name() { python3 -c "import json,sys;d=json.load(open('$REPO/terraform/envs/'+sys.argv[1]+'/names.auto.tfvars.json'))
for k in sys.argv[2].split('.'): d=d[k]
print(d)" "$1" "$2"; }
tf() { local root=$1; shift; (cd "$REPO/terraform/envs/$root" && AZURE_CONFIG_DIR=$AZ_WRITE TF_DATA_DIR=$REPO/.scratch_tf/$root \
  terraform "$@"); }
database() { case $1 in dev) echo erp-dev ;; stg) echo erp-stg ;; esac; }

cmd=${1:-}; shift || true
case "$cmd" in
tf) root=$1; shift; tf "$root" "$@" -no-color 2>&1 | mask ;;
plan)
  # a failed plan must leave no plan behind: apply would otherwise apply the previous one (2026-11-08)
  plan=$REPO/.scratch_tf/$1/$1.tfplan; rm -f "$plan"
  set +e; tf "$1" plan -input=false -no-color -out="$plan" > "$plan.log" 2>&1; rc=$?; set -e
  mask < "$plan.log" | grep -E '^  # |^Plan:|^No changes|Error' || true
  if [ $rc -ne 0 ] || [ ! -s "$plan" ]; then rm -f "$plan"; echo "plan failed (exit $rc): nothing to apply" >&2; exit 1; fi
  tf "$1" show -json "$plan" | python3 "$REPO/tools/no-repo-trace.py" || { rm -f "$plan"; exit 1; }
  # the ground rules as code (policy/terraform/plan.rego); a refused plan is deleted, so apply has nothing to apply
  set +e; tf "$1" show -json "$plan" | bash "$REPO/tools/policy.sh" plan > "$plan.policy" 2>&1; rc=$?; set -e
  mask < "$plan.policy" | grep -E '^FAIL|tests,|rror' || true; rm -f "$plan.policy"
  if [ $rc -ne 0 ]; then rm -f "$plan"; echo "policy refused the plan (exit $rc): nothing to apply" >&2; exit 1; fi ;;
drift)
  # every root planned against the live resources: read only, no lock (a plan writes no state, and a running apply is
  # not disturbed), no plan file. Exit 0: code and Azure match; 2: a root differs; 1: a plan failed
  log=$(mktemp); trap 'rm -f "$log"' EXIT; worst=0
  for root in shared dev stg; do
    set +e; tf "$root" plan -lock=false -input=false -no-color -detailed-exitcode > "$log" 2>&1; rc=$?; set -e
    case $rc in
      0) echo "$root: no drift" ;;
      2) echo "$root: DRIFT"; mask < "$log" | grep -E '^  # |^Plan:'; [ $worst -eq 1 ] || worst=2 ;;
      *) echo "$root: plan failed (exit $rc)"; mask < "$log" | grep -E 'Error' | head -5; worst=1 ;;
    esac
  done
  exit $worst ;;
apply)
  plan=$REPO/.scratch_tf/$1/$1.tfplan
  [ -s "$plan" ] || { echo "no plan for $1: run obs.sh plan $1 first" >&2; exit 1; }
  tf "$1" apply -input=false -no-color "$plan" 2>&1 | mask | grep -E 'complete|Error|error' | sed -E 's/ \[id=[^]]*\]//'
  rm -f "$plan" ;;
role)
  env=$1 svc=$2
  OBS_MONITOR_VERIFIER=$(tf "$env" output -raw obs_monitor_password | python3 "$REPO/sql/scram.py")
  export OBS_MONITOR_VERIFIER
  # the service is read-only by default (the lab's guard); lifted for this connection only, which names itself obs-setup
  psql "service=$svc application_name=obs-setup options='-c default_transaction_read_only=off -c statement_timeout=60s'" \
    -X -v ON_ERROR_STOP=1 -f "$REPO/sql/obs_monitor.sql" 2>&1 | mask ;;
role-check)
  env=$1 svc=$2
  host=$(awk -F= -v s="[$svc]" '/^\[/{in_s=($0==s)} in_s && $1=="host"{print $2}' "$PGSERVICEFILE")
  PGPASSWORD=$(tf "$env" output -raw obs_monitor_password) psql "host=$host dbname=$(database "$env") user=obs_monitor \
    sslmode=require application_name=obs-a1" -X -v ON_ERROR_STOP=1 -f "$REPO/sql/check_obs_monitor.sql" 2>&1 | mask
  psql "service=$svc application_name=obs-check" -X -c "select grantor, table_name, privilege_type from information_schema.role_table_grants
    where grantee = 'obs_monitor' order by 2" 2>&1 | mask ;;
push)
  tag=$1 acr=$(name stg registry.name) sub=$(name stg subscription_ids.stg)
  export AZURE_CONFIG_DIR=$AZ_WRITE
  server=$(az acr show --subscription "$sub" -n "$acr" --query loginServer -o tsv)
  docker build -q -t "obs/sql-job:$tag" "$REPO/job"
  docker image inspect "obs/sql-job:$tag" --format '{{json .Config}}' | python3 "$REPO/tools/no-repo-trace.py"
  docker history --no-trunc --format '{{.CreatedBy}}' "obs/sql-job:$tag" | python3 "$REPO/tools/no-repo-trace.py"
  docker run --rm --entrypoint sh "obs/sql-job:$tag" -c 'cat /app/*' | python3 "$REPO/tools/no-repo-trace.py"
  az acr login --subscription "$sub" -n "$acr" 2>&1 | tail -1
  docker tag "obs/sql-job:$tag" "$server/obs/sql-job:$tag"
  docker push -q "$server/obs/sql-job:$tag" | mask
  az acr repository show-tags --subscription "$sub" -n "$acr" --repository obs/sql-job -o tsv ;;
ag-test)
  env=$1 group=$2 ag=erp-mgmt-obs-$1-$2-ag
  export AZURE_CONFIG_DIR=$AZ_WRITE
  # the test must repeat the receiver exactly as the action group stores it
  mapfile -t r < <(az monitor action-group show --subscription management-sub -g erp-mgmt-obs-rg -n "$ag" \
    --query "logicAppReceivers[0].[name,resourceId,callbackUrl]" -o tsv | tr '\t' '\n')
  name=${r[0]} id=${r[1]} cb=${r[2]}
  az monitor action-group test-notifications create --subscription management-sub \
    -g erp-mgmt-obs-rg --action-group-name "$ag" --alert-type logalertv2 \
    -a logicapp "$name" "$id" "$cb" usecommonalertschema --query "{state:state,details:actionDetails}" -o json 2>&1 | mask
  az rest --method get --url "https://management.azure.com$id/runs?api-version=2016-06-01&\$top=1" \
    --query "value[].{start:properties.startTime,status:properties.status}" -o table ;;
job)
  env=$1 sub=$(name "$1" "subscription_ids.$1") kind=$([ "${3:-}" = log ] && echo logscan || echo sqljob)
  j=(--subscription "$sub" -g "erp-$env-obs-rg" -n "erp-$env-obs-$kind-caj")
  export AZURE_CONFIG_DIR=$AZ_WRITE
  case $2 in
  start) az containerapp job start "${j[@]}" --query name -o tsv ;;
  list) az containerapp job execution list "${j[@]}" \
          --query "[].{name:name,status:properties.status,start:properties.startTime,end:properties.endTime}" -o table ;;
  esac ;;
kq)
  AZURE_CONFIG_DIR=$AZ_READ az monitor log-analytics query -w "$(name shared workspace_customer_id)" \
    --analytics-query "$1" --timespan "${2:-PT2H}" -o table 2>&1 | mask ;;
kq-env)
  # the environment's targets as let statements, so a query in a runbook names no app, server or gateway (AGENTS.md):
  # Apps, Web, Cron (the Odoo apps), Servers (the Postgres server), Gateway; role(app) gives "web", "cron" or "other"
  lets=$(python3 -c "import json,sys;n=json.load(open('$REPO/terraform/envs/'+sys.argv[1]+'/names.auto.tfvars.json'))
a=[x['name'] for x in n['apps']];j=json.dumps
print('let Apps = dynamic(%s); let Web = dynamic(%s); let Cron = dynamic(%s); let Servers = dynamic(%s); let Gateway = %s;'
  % (j(a), j([x for x in a if 'cron' not in x]), j([x for x in a if 'cron' in x]), j([n['pg_server']['name']]), j(n['gateway']['name'])))
print('let role = (app:string) { iff(app in~ (Web), \\'web\\', iff(app in~ (Cron), \\'cron\\', \\'other\\')) };')" "$1")
  AZURE_CONFIG_DIR=$AZ_READ az monitor log-analytics query -w "$(name shared workspace_customer_id)" \
    --analytics-query "$lets
$2" --timespan "${3:-PT2H}" -o table 2>&1 | mask ;;
trace-live)
  AZURE_CONFIG_DIR=$AZ_WRITE az graph query --first 1000 -o json -q "resources | union resourcecontainers
    | where tags.owner == 'observability-track' | project type, name, resourceGroup, tags, properties" \
    | python3 "$REPO/tools/no-repo-trace.py" ;;
inventory)
  export AZURE_CONFIG_DIR=$AZ_WRITE
  subs="resourcecontainers | where type == 'microsoft.resources/subscriptions' | project subscriptionId, sub=name"
  echo "== resources tagged owner=observability-track (subscription | resource group | type | name)"
  az graph query --first 500 -o json -q "resources | union resourcecontainers | where tags.owner == 'observability-track'
    | join kind=leftouter ($subs) on subscriptionId | project sub, resourceGroup, type, name
    | order by sub asc, resourceGroup asc, type asc, name asc" --query "data[].[sub,resourceGroup,type,name]" \
    | python3 -c "import json,sys;[print(' | '.join(r)) for r in json.load(sys.stdin)]"
  echo "== role assignments for the track (subscription | role | on | to)"
  pids=$(az graph query -o json -q "resources | where type == 'microsoft.managedidentity/userassignedidentities'
    and tags.owner == 'observability-track' | project p=tostring(properties.principalId)" --query "data[].p" \
    | python3 -c "import json,sys;print(','.join(\"'\"+p+\"'\" for p in json.load(sys.stdin)))")
  me=$(az ad signed-in-user show --query id -o tsv)
  az graph query --first 100 -o json -q "authorizationresources | where type == 'microsoft.authorization/roleassignments'
    | extend scope=tostring(properties.scope), principalId=tostring(properties.principalId), roleId=tostring(split(tostring(properties.roleDefinitionId),'/')[-1])
    | where principalId in ($pids) or (principalId == '$me' and scope has 'erp-mgmt-obs-rg')
    | join kind=leftouter ($subs) on subscriptionId
    | project sub, roleId, on=tostring(split(scope,'/')[-1]), to=iff(principalId == '$me', 'the owner (state)', 'the job identity'),
      conditioned=isnotempty(properties.condition)" --query "data[].[sub,roleId,on,to,conditioned]" \
    | python3 -c "
import json,subprocess,sys
for sub, rid, on, to, cond in json.load(sys.stdin):
    role = subprocess.run(['az','role','definition','list','--name',rid,'--query','[0].roleName','-o','tsv'],capture_output=True,text=True).stdout.strip()
    print(' | '.join([sub, role + (' (conditioned)' if cond else ''), on, to]))" | mask
  echo "== custom tables in platform-logs"
  az monitor log-analytics workspace table list --subscription management-sub -g monitor-rg \
    --workspace-name platform-logs --query "[?starts_with(name,'Odoo')].[name,plan,retentionInDays]" -o tsv
  echo "== image repository in the stg registry"
  az acr repository show-tags --subscription "$(name stg subscription_ids.stg)" -n "$(name stg registry.name)" \
    --repository obs/sql-job -o tsv | sed 's#^#obs/sql-job:#' ;;
audit)
  export AZURE_CONFIG_DIR=$AZ_WRITE
  T="python3 $REPO/tools/no-repo-trace.py"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  echo "== resources tagged owner=observability-track, full ARM bodies"
  mapfile -t ids < <(az graph query --first 500 -o tsv -q "resources | where tags.owner == 'observability-track' | project id" --query "data[].id")
  echo "${#ids[@]} resources"; az resource show --ids "${ids[@]}" -o json | $T
  echo "== resource groups"
  az graph query -o json -q "resourcecontainers | where tags.owner == 'observability-track'" | $T
  echo "== role assignments of the track's identities and on its state account"
  pids=$(az graph query -o json -q "resources | where type == 'microsoft.managedidentity/userassignedidentities' and tags.owner == 'observability-track' | project p=tostring(properties.principalId)" --query "data[].p" | python3 -c "import json,sys;print(','.join(\"'\"+p+\"'\" for p in json.load(sys.stdin)))")
  az graph query --first 100 -o json -q "authorizationresources | where type == 'microsoft.authorization/roleassignments' and (tostring(properties.principalId) in ($pids) or tostring(properties.scope) has 'erp-mgmt-obs-rg') | project properties" | $T
  echo "== Terraform state"
  acct=$(name shared state.account)
  for k in shared dev stg; do
    az storage blob download --account-name "$acct" -c tfstate -n $k.tfstate --auth-mode login -f "$tmp/$k" -o none 2>/dev/null || continue
    echo -n "$k.tfstate: "; $T < "$tmp/$k" | tail -1
  done
  echo "== the image's manifests in the stg registry, attestations included"
  server=$(az acr show --subscription "$(name stg subscription_ids.stg)" -n "$(name stg registry.name)" --query loginServer -o tsv)
  # its own registry login: a token left by an earlier push expires (401 on 2026-11-08), and the sections below must run
  az acr login --subscription "$(name stg subscription_ids.stg)" -n "$(name stg registry.name)" 2>&1 | mask | tail -1 || true
  for tag in $(az acr repository show-tags --subscription "$(name stg subscription_ids.stg)" -n "$(name stg registry.name)" --repository obs/sql-job -o tsv); do
    echo -n "obs/sql-job:$tag: "; docker buildx imagetools inspect "$server/obs/sql-job:$tag" --format '{{json .}}' | $T | tail -1
  done
  echo "== the workspace, the last day"
  ws=$(name shared workspace_customer_id)
  for kq in 'union OdooQueue_CL, OdooCron_CL, OdooHeartbeat_CL' \
            'ContainerAppConsoleLogs_CL | where ContainerJobName_s startswith "erp-" and ContainerJobName_s has "-obs-"' \
            'search "caokgit" or "erp-observability" | take 50'; do
    AZURE_CONFIG_DIR=$AZ_READ az monitor log-analytics query -w "$ws" --analytics-query "$kq" --timespan P1D -o json 2>/dev/null | $T
  done
  echo "-- application names in the Postgres logs that are not the track's (obs-*) nor Odoo's"
  AZURE_CONFIG_DIR=$AZ_READ az monitor log-analytics query -w "$ws" --timespan P1D -o table --analytics-query 'union AzureDiagnostics, PGSQLServerLogs
    | where Category == "PostgreSQLLogs" or isnotempty(column_ifexists("Message", ""))
    | extend app = extract(@"application_name=([A-Za-z0-9_.-]+)", 1, tostring(column_ifexists("Message", "")))
    | where isnotempty(app) and app !startswith "obs-" and app !startswith "odoo-" and app !in ("psql", "pg_dump")
    | summarize lines = count(), lastSeen = max(TimeGenerated) by app' 2>/dev/null | mask
  echo "== the Activity Log of the track's groups, the last 90 days"
  for g in "management-sub erp-mgmt-obs-rg" "$(name dev subscription_ids.dev) erp-dev-obs-rg" \
           "$(name stg subscription_ids.stg) erp-stg-obs-rg"; do
    set -- $g
    az monitor activity-log list --subscription "$1" -g "$2" --offset 90d --max-events 5000 -o json 2>/dev/null > "$tmp/al"
    echo -n "$2: "; python3 - "$tmp/al" <<'PY'
import json, re, sys
ev = json.load(open(sys.argv[1])); t = re.compile(r"caokgit|erp-observability|github", re.I)
hits = [f'{e["eventTimestamp"][:19]} {e["operationName"]["value"]}' for e in ev if t.search(json.dumps(e))]
print(f"{len(ev)} events, {len(hits)} with a trace of the repo" + "".join("\n   " + h for h in hits))
PY
  done ;;
drill-lock)
  svc=$1 secs=$2 key=424242
  conn="service=$svc application_name=obs-drill options='-c statement_timeout=$((secs + 60))s -c lock_timeout=0'"
  date -u +"holder starts %H:%M:%S"
  psql "$conn" -X -At -c "select pg_advisory_lock($key), pg_sleep($secs), pg_advisory_unlock($key)" >/dev/null &
  sleep 3
  date -u +"waiter starts %H:%M:%S"
  psql "$conn" -X -At -c "select pg_advisory_lock($key), pg_advisory_unlock($key)" >/dev/null
  date -u +"waiter got the lock %H:%M:%S"
  wait ;;
*) sed -n '2,27p' "$0"; exit 2 ;;
esac
