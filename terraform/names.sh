#!/usr/bin/env bash
# Write the names the track's Terraform and backtests need into the files the roots read (committed: AGENTS.md#writing), from read-only az queries
# (docs/specs/round-1.md#terraform, "Names"): server, app and registry names and subscription ids never sit in the
# code. Each resource is found by its role, not by its name:
#   Postgres server   the only flexible server in the environment's database resource group
#   Odoo apps         Container Apps in the environment's erp resource group whose container "main" runs a
#                     erp/ image (stg: the web and cron apps; dev: the one Odoo app)
#   job environment   the only Container Apps environment in that resource group (stg: the stg Odoo environment);
#                     if there is none (dev), the Odoo app's environment
#   registry          the only registry in shared-stg-rg (D12)
#   VPN gateway       the only virtual network gateway in network-rg
# Writes terraform/envs/{shared,dev,stg}/names.auto.tfvars.json and .scratch_mask/mask-words (for tools/mask.py: the names
# above, the servers' and apps' hostnames' first labels, the subscription ids).
# Usage: AZURE_CONFIG_DIR=... bash terraform/names.sh
set -euo pipefail
cd "$(dirname "$0")/.."

sub_id() { az account show --subscription "$1" --query id -o tsv; }
only() {  # only <subscription> <resource group> <resource type>: the name of the single resource of that type
  local names; names=$(az resource list --subscription "$1" -g "$2" --resource-type "$3" --query "[].name" -o tsv)
  [ "$(printf '%s\n' "$names" | grep -c .)" = 1 ] || { echo "expected one $3 in $2, found: $(printf '%s' "$names" | grep -c .)" >&2; exit 1; }
  printf '%s' "$names"
}
odoo_apps() {  # odoo_apps <subscription> <resource group>: JSON list of {name, environment}
  az containerapp list --subscription "$1" -g "$2" --query "[?length(properties.template.containers[?name=='main' && contains(image, '/erp/')]) > \`0\`].{name: name, environment: properties.environmentId}" -o json
}
app_hosts() {  # app_hosts <subscription> <resource group>: every Odoo app's ingress FQDN and custom domains, one a line
  az containerapp list --subscription "$1" -g "$2" --query "[?length(properties.template.containers[?name=='main' && contains(image, '/erp/')]) > \`0\`].[properties.configuration.ingress.fqdn, properties.configuration.ingress.customDomains[].name][][]" -o tsv
}
app_registries() {  # app_registries <subscription> <resource group>: the registry host of every image the apps run
  az containerapp list --subscription "$1" -g "$2" --query "[].properties.template.containers[].image" -o tsv | cut -d/ -f1 | sort -u
}
local_env() {  # local_env <subscription> <resource group>: the environment in that group, or nothing
  az containerapp env list --subscription "$1" -g "$2" --query "[].id" -o tsv
}

declare -A SUB
for s in management dev stg prd connectivity; do SUB[$s]=$(sub_id "$s-sub"); done
WS_CUSTOMER_ID=$(az monitor log-analytics workspace show --subscription management-sub -g monitor-rg -n platform-logs --query customerId -o tsv)
GATEWAY=$(only connectivity-sub network-rg Microsoft.Network/virtualNetworkGateways)
REGISTRY=$(only stg-sub shared-stg-rg Microsoft.ContainerRegistry/registries)
PG_DEV=$(only dev-sub database-dev-rg Microsoft.DBforPostgreSQL/flexibleServers)
PG_PRD=$(only prd-sub database-prd-rg Microsoft.DBforPostgreSQL/flexibleServers)
PG_STG=$(only stg-sub database-stg-rg Microsoft.DBforPostgreSQL/flexibleServers)
FQDN_DEV=$(az postgres flexible-server show --subscription dev-sub -g database-dev-rg -n "$PG_DEV" --query fullyQualifiedDomainName -o tsv)
FQDN_PRD=$(az postgres flexible-server show --subscription prd-sub -g database-prd-rg -n "$PG_PRD" --query fullyQualifiedDomainName -o tsv)
APPS_DEV=$(odoo_apps dev-sub erp-dev-rg)
APPS_STG=$(odoo_apps stg-sub erp-stg-rg)
HOSTS=$(app_hosts dev-sub erp-dev-rg; app_hosts stg-sub erp-stg-rg)
REGISTRIES=$(app_registries dev-sub erp-dev-rg; app_registries stg-sub erp-stg-rg)
ENV_DEV=$(local_env dev-sub erp-dev-rg)
ENV_STG=$(local_env stg-sub erp-stg-rg)

export SUB_JSON=$(for k in "${!SUB[@]}"; do printf '%s=%s\n' "$k" "${SUB[$k]}"; done)
export WS_CUSTOMER_ID GATEWAY REGISTRY PG_DEV PG_PRD PG_STG FQDN_DEV FQDN_PRD HOSTS REGISTRIES APPS_DEV APPS_STG ENV_DEV ENV_STG
python3 - <<'PY'
import json, os, pathlib
e = os.environ
subs = dict(line.split("=", 1) for line in e["SUB_JSON"].splitlines())
common = {"subscription_ids": subs, "workspace_customer_id": e["WS_CUSTOMER_ID"],
          "gateway": {"name": e["GATEWAY"], "resource_group": "network-rg"},
          "registry": {"name": e["REGISTRY"], "resource_group": "shared-stg-rg"}}

def env_names(apps_json, local_env, rg, pg, pg_rg, fqdn, pg_sub, history):
    apps = json.loads(apps_json)
    if not apps:
        raise SystemExit(f"no Odoo app found in {rg}")
    envs = local_env.split() or sorted({a["environment"] for a in apps})
    if len(envs) != 1:
        raise SystemExit(f"expected one job environment for {rg}, found {len(envs)}")
    env_id = envs[0].split("/")
    return {**common,
            "pg_server": {"name": pg, "resource_group": pg_rg, "fqdn": fqdn, "subscription": pg_sub},
            "pg_servers_history": history,
            "apps": [{"name": a["name"], "resource_group": rg} for a in apps],
            "job_environment": {"name": env_id[-1], "resource_group": env_id[[x.lower() for x in env_id].index("resourcegroups") + 1]}}

out = {
    "shared": common,
    "dev": env_names(e["APPS_DEV"], e["ENV_DEV"], "erp-dev-rg", e["PG_DEV"], "database-dev-rg", e["FQDN_DEV"], "dev",
                     [{"name": e["PG_DEV"], "until": ""}]),
    # stg's database moved from the stg server to the prd server on 2026-08-27 (docs/platform.md); backtests need both
    "stg": env_names(e["APPS_STG"], e["ENV_STG"], "erp-stg-rg", e["PG_PRD"], "database-prd-rg", e["FQDN_PRD"], "prd",
                     [{"name": e["PG_STG"], "until": "2026-08-27T00:00:00Z"}, {"name": e["PG_PRD"], "until": ""}]),
}
for env, names in out.items():
    path = pathlib.Path(f"terraform/envs/{env}/names.auto.tfvars.json")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(names, indent=2) + "\n")
    path.chmod(0o600)
words = {e[k] for k in ("GATEWAY", "REGISTRY", "PG_DEV", "PG_PRD", "PG_STG", "WS_CUSTOMER_ID")}
words |= {f.split(".")[0] for f in (e["FQDN_DEV"], e["FQDN_PRD"])} | set(subs.values())
# the apps' public hostnames show in nginx's Referer and Host fields (2026-11-08: one slipped through unmasked)
words |= {h.split(".")[0] for h in e["HOSTS"].split() if h}
# every registry the apps' images name: dev's showed in an image listing (2026-11-08), the mask held only stg's
words |= {r.split(".")[0] for r in e["REGISTRIES"].split() if r.endswith(".azurecr.io")}
words |= {a["name"] for env in ("dev", "stg") for a in out[env]["apps"]}
words |= {out[env]["job_environment"]["name"] for env in ("dev", "stg")}
mask = pathlib.Path(".scratch_mask/mask-words"); mask.parent.mkdir(exist_ok=True)
mask.write_text("\n".join(sorted(words)) + "\n"); mask.chmod(0o600)
print("wrote", ", ".join(f"terraform/envs/{env}/names.auto.tfvars.json" for env in out), "and .scratch_mask/mask-words")
print({env: {"apps": len(n.get("apps", [])), "job_environment": "job_environment" in n} for env, n in out.items()})
PY

# The state backend, once terraform/state-storage.sh has created it: one backend.hcl per root
ACCOUNT=$(az storage account list --subscription management-sub -g erp-mgmt-obs-rg --query "[0].name" -o tsv 2>/dev/null || true)
if [ -n "$ACCOUNT" ]; then
  for env in shared dev stg; do
    printf 'subscription_id      = "%s"\nresource_group_name  = "erp-mgmt-obs-rg"\nstorage_account_name = "%s"\ncontainer_name       = "tfstate"\nkey                  = "%s.tfstate"\nuse_azuread_auth     = true\n' \
      "${SUB[management]}" "$ACCOUNT" "$env" > "terraform/envs/$env/backend.hcl"
    chmod 600 "terraform/envs/$env/backend.hcl"
    python3 - "$env" "$ACCOUNT" <<'PY'
import json, pathlib, sys
env, account = sys.argv[1], sys.argv[2]
path = pathlib.Path(f"terraform/envs/{env}/names.auto.tfvars.json")
names = json.loads(path.read_text())
names["state"] = {"resource_group": "erp-mgmt-obs-rg", "account": account, "container": "tfstate"}
path.write_text(json.dumps(names, indent=2) + "\n")
PY
  done
  echo "wrote terraform/envs/{shared,dev,stg}/backend.hcl"
else
  echo "no state storage yet (terraform/state-storage.sh): backend.hcl not written"
fi
