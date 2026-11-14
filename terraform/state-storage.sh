#!/usr/bin/env bash
# The track's Terraform state storage (docs/specs/round-1.md#terraform, D13): created once by az before the first
# terraform init, removed last, after every destroy. Entra ID auth only (no shared keys), versioning on.
#   bash terraform/state-storage.sh plan      print what would be created, change nothing
#   bash terraform/state-storage.sh apply     create (Manual mode, after the owner's go)
#   bash terraform/state-storage.sh destroy   delete the resource group with the account (teardown, last step)
# After apply, run terraform/names.sh: it writes each root's backend.hcl.
set -euo pipefail
MODE=${1:-plan}
SUB=management-sub
RG=erp-mgmt-obs-rg
ACCOUNT=obstfstate # 01 deleted 2026-11-08, its name held 14 days by the soft delete
LOCATION=southeastasia
CONTAINER=tfstate
TAGS=(owner=observability-track purpose=terraform-state) # nothing naming the repo (AGENTS.md)

run() { if [ "$MODE" = apply ] || [ "$MODE" = destroy ]; then "$@"; else printf '+ %s\n' "$*"; fi; }

case "$MODE" in
  plan|apply)
    echo "resource group exists: $(az group exists --subscription $SUB -n $RG)"
    echo "account name available: $(az storage account check-name -n $ACCOUNT --query nameAvailable -o tsv)"
    run az group create --subscription $SUB -n $RG -l $LOCATION --tags "${TAGS[@]}" -o none
    run az storage account create --subscription $SUB -g $RG -n $ACCOUNT -l $LOCATION --sku Standard_LRS --kind StorageV2 \
      --min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false --https-only true \
      --tags "${TAGS[@]}" -o none
    run az storage account blob-service-properties update --subscription $SUB -g $RG --account-name $ACCOUNT \
      --enable-versioning true -o none
    ME=$(az ad signed-in-user show --query id -o tsv)
    SCOPE="$(az group show --subscription $SUB -n $RG --query id -o tsv 2>/dev/null || echo "<the group's id>")/providers/Microsoft.Storage/storageAccounts/$ACCOUNT"
    run az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
      --role "Storage Blob Data Contributor" --scope "$SCOPE" -o none
    # the container through ARM: the management role suffices, no wait for the data role to propagate
    run az storage container-rm create --subscription $SUB -g $RG --storage-account $ACCOUNT -n $CONTAINER -o none
    echo "terraform reads and writes state through the data role, which takes up to a few minutes to apply"
    ;;
  destroy)
    run az group delete --subscription $SUB -n $RG --yes
    ;;
  *) echo "usage: $0 plan|apply|destroy" >&2; exit 2 ;;
esac
