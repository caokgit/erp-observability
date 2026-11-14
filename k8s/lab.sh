#!/usr/bin/env bash
# The Kubernetes mapping's lab (docs/specs/kubernetes-mapping.md): one kind node, the lab repo's monitoring charts and
# values, the demonstration ERP, the translated rules, drills timed at the alert sink. Laptop only; nothing reaches
# The client's Azure. Tools and the lab's values come from the lab repo by path; the kubeconfig stays in .scratch_kube.
#
#   bash k8s/lab.sh up            the cluster, monitoring, the sink, the ERP, the rules, the dashboard (rerunnable)
#   bash k8s/lab.sh rules         re-apply only the rules and the dashboard
#   bash k8s/lab.sh drill <name>  lock | http5xx | cron | oom | exporter | heavy | bloat | limit: make one rule fire
#   bash k8s/lab.sh sink          the sink's log: every notification with its arrival time
#   bash k8s/lab.sh check         the dashboard and its panels' last 40 minutes, through Grafana
#   bash k8s/lab.sh down          delete the cluster
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd); cd "$REPO"
LAB=$HOME/lab
export PATH=$LAB/.toolchain/bin:$PATH KUBECONFIG=$REPO/.scratch_kube/obs-lab.yaml
export HELM_CACHE_HOME=$REPO/.scratch_kube/helm/cache HELM_CONFIG_HOME=$REPO/.scratch_kube/helm/config HELM_DATA_HOME=$REPO/.scratch_kube/helm/data
VALUES=$LAB/infra/platform/values
K=(kubectl)
ts() { date -u +%H:%M:%S; }

up_platform() {
  kind get clusters 2>/dev/null | grep -qx obs-lab || kind create cluster --config k8s/kind.yaml
  "${K[@]}" create namespace monitoring --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null
  rules_loki
  helm upgrade --install kps kube-prometheus-stack --repo https://prometheus-community.github.io/helm-charts \
    --version 92.17.1 -n monitoring -f "$VALUES/kube-prometheus-stack/common.yaml" -f "$VALUES/kube-prometheus-stack/kind.yaml" \
    -f k8s/values/kps.yaml --wait --timeout 15m >/dev/null
  helm upgrade --install loki loki --repo https://grafana.github.io/helm-charts --version 7.5.0 -n monitoring \
    -f "$VALUES/loki/common.yaml" -f "$VALUES/loki/kind.yaml" -f k8s/values/loki.yaml --wait --timeout 10m >/dev/null
  helm upgrade --install alloy alloy --repo https://grafana.github.io/helm-charts --version 1.15.0 -n monitoring \
    -f "$VALUES/alloy/common.yaml" --wait --timeout 5m >/dev/null
  "${K[@]}" apply -f k8s/manifests/alert-sink.yaml >/dev/null
  echo "$(ts) monitoring up"
}

rules_loki() {  # the LogQL rules as the ConfigMap Loki's ruler reads
  "${K[@]}" -n monitoring create configmap loki-rules --from-file=erp.yaml=k8s/rules/loki-rules.yaml \
    --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null
}

rules() {  # the PromQL rules as a PrometheusRule, the LogQL rules for Loki, the dashboard
  { printf 'apiVersion: monitoring.coreos.com/v1\nkind: PrometheusRule\nmetadata:\n  name: erp\n  namespace: monitoring\nspec:\n'
    sed 's/^/  /' k8s/rules/erp.rules.yaml; } | "${K[@]}" apply -f - >/dev/null
  rules_loki
  "${K[@]}" -n monitoring create configmap erp-dashboard --from-file=erp.json=k8s/dashboards/erp.json \
    --dry-run=client -o yaml | "${K[@]}" label --local -f - grafana_dashboard=1 -o yaml | "${K[@]}" apply -f - >/dev/null
  echo "$(ts) rules and dashboard applied"
}

up_erp() {
  "${K[@]}" create namespace erp --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null
  "${K[@]}" -n erp create configmap incident-lab \
    $(for f in k8s/addons/incident_lab/*; do printf -- '--from-file=%s ' "$f"; done) \
    --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null
  "${K[@]}" apply -f k8s/manifests/erp.yaml >/dev/null
  "${K[@]}" -n erp rollout status deploy/postgres --timeout 5m >/dev/null
  "${K[@]}" -n erp rollout status deploy/odoo --timeout 15m >/dev/null
  "${K[@]}" -n erp rollout status deploy/postgres-exporter --timeout 5m >/dev/null
  # Q1's source, in the database Odoo created (the library is loaded by the server's start arguments)
  "${K[@]}" -n erp exec deploy/postgres -- psql -U odoo -d erp -qc 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements'
  echo "$(ts) erp up"
}

drill() {
  echo "$(ts) drill $1 starts"
  case $1 in
    lock)      # L1: one session holds an advisory lock 150 s while a second waits (as on Azure's dev server); long
               # enough that the page can arrive during the wait (60 s, a 15 s scrape, a 15 s evaluation, 10 s grouping)
      "${K[@]}" -n erp exec deploy/odoo -- curl -s -o /dev/null "http://localhost:8069/incident_lab/hold_lock/150" &
      sleep 2
      { "${K[@]}" -n erp exec deploy/odoo -- curl -s "http://localhost:8069/incident_lab/wait_lock"; echo "$(ts) the waiter returned"; } &
      wait ;;
    http5xx)   # L2 and SLO-fast: 40 requests answered 500 in a minute, on the interactive journey
      for i in $(seq 40); do "${K[@]}" -n erp exec deploy/odoo -- curl -s -o /dev/null "http://localhost:8069/incident_lab/status/500"; done ;;
    cron)      # L6: the lab's 1-minute task sleeps 200 s, so its next run falls behind
      "${K[@]}" -n erp exec deploy/odoo -- curl -s "http://localhost:8069/incident_lab/cron_sleep/200"; echo ;;
    oom)       # L7 and M1: a request allocates past the container's memory limit
      "${K[@]}" -n erp exec deploy/odoo -- curl -s -m 30 -o /dev/null "http://localhost:8069/incident_lab/allocate/1200" || true ;;
    heavy)     # Q1: 16 sessions in pg_sleep(360) at once, about 96 min of database time, counted when they end (a
               # stand-in for a heavy query family)
      for i in $(seq 16); do
        "${K[@]}" -n erp exec deploy/postgres -- psql -U odoo -d erp -qAtc 'SELECT pg_sleep(360)' >/dev/null &
      done
      wait ;;
    bloat)     # T1: a table with autovacuum off, 120,000 rows inserted then all updated: 120,000 dead rows, half the table
      "${K[@]}" -n erp exec deploy/postgres -- psql -U odoo -d erp -qc "DROP TABLE IF EXISTS lab_bloat;
        CREATE TABLE lab_bloat (id int, v int) WITH (autovacuum_enabled = false);
        INSERT INTO lab_bloat SELECT g, 0 FROM generate_series(1, 120000) g; UPDATE lab_bloat SET v = 1;" ;;
    limit)     # O1: one request holds a lock 240 s while three wait; the threaded server checks every 60 s, so at least one
               # check finds all four past the 120 s real-time limit, logs each, then reloads
      "${K[@]}" -n erp exec deploy/odoo -- curl -s -o /dev/null "http://localhost:8069/incident_lab/hold_lock/240" &
      sleep 2
      for i in 1 2 3; do "${K[@]}" -n erp exec deploy/odoo -- curl -s -o /dev/null "http://localhost:8069/incident_lab/wait_lock" & done
      wait ;;
    exporter)  # H: the exporter stops for 4 min
      "${K[@]}" -n erp scale deploy/postgres-exporter --replicas 0 >/dev/null; sleep 240
      "${K[@]}" -n erp scale deploy/postgres-exporter --replicas 1 >/dev/null ;;
    *) echo "unknown drill $1" >&2; exit 2 ;;
  esac
  echo "$(ts) drill $1 done"
}

check() {  # K6: the dashboard is loaded and its panels' queries return the last 40 minutes, through Grafana
  "${K[@]}" -n monitoring port-forward svc/kps-grafana 3300:80 >/dev/null 2>&1 & local pf=$!
  sleep 4
  local auth; auth="admin:$("${K[@]}" -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
  g() { curl -s --user "$auth" "http://127.0.0.1:3300$1" "${@:2}"; }
  g /api/dashboards/uid/erp-signals | python3 -c "import json,sys;d=json.load(sys.stdin)['dashboard'];print(d['title'], '-', len(d['panels']), 'panels')"
  for q in 'max_over_time(max(erp_lock_wait_max_seconds)[40m:15s])' 'max_over_time(sum(erp:requests_bad:count5m)[40m:15s])' \
           'max_over_time(erp:slo_bad_ratio:5m[40m:15s])' 'max(max_over_time(erp_cron_overdue_seconds{name="Incident lab: one-minute task"}[40m]))' \
           'max(max_over_time(kube_pod_container_status_restarts_total{namespace="erp",container="odoo"}[40m]))' \
           'max_over_time((sum(increase(erp_db_time_seconds_total[1h])) / 60)[40m:15s])' \
           'max(max_over_time(erp_table_dead_rows{table="lab_bloat"}[40m]))'; do
    printf '%-60s ' "${q:0:60}"
    g /api/datasources/proxy/uid/prometheus/api/v1/query --get --data-urlencode "query=$q" \
      | python3 -c "import json,sys;r=json.load(sys.stdin)['data']['result'];print([(x['metric'].get('journey',''),round(float(x['value'][1]),3)) for x in r])"
  done
  kill "$pf"
}

case "${1:-}" in
  up) up_platform; up_erp; rules ;;
  platform) up_platform ;;
  erp) up_erp ;;
  rules) rules ;;
  drill) drill "${2:?drill name}" ;;
  sink) "${K[@]}" -n monitoring logs deploy/alert-sink ;;
  check) check ;;
  down) kind delete cluster --name obs-lab ;;
  *) echo "usage: $0 up|platform|erp|rules|drill <name>|sink|check|down" >&2; exit 2 ;;
esac
