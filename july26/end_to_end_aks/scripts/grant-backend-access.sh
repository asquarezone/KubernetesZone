#!/usr/bin/env bash
# Grants the data-plane role Terraform needs to read/write remote state.
# Fixes: "403 AuthorizationPermissionMismatch" on terraform init.
set -euo pipefail

SA="${1:?usage: $0 <storage-account-name> [resource-group]}"
RG="${2:-rg-tfstate-aksstore}"

SCOPE="$(az storage account show -n "$SA" -g "$RG" --query id -o tsv)"

if [[ -n "${ARM_CLIENT_ID:-}" ]]; then
  OBJ_ID="$(az ad sp show --id "$ARM_CLIENT_ID" --query id -o tsv)"
  PTYPE="ServicePrincipal"
  echo "Granting to service principal $ARM_CLIENT_ID"
else
  OBJ_ID="$(az ad signed-in-user show --query id -o tsv)"
  PTYPE="User"
  echo "Granting to signed-in user"
fi

az role assignment create \
  --assignee-object-id "$OBJ_ID" \
  --assignee-principal-type "$PTYPE" \
  --role "Storage Blob Data Contributor" \
  --scope "$SCOPE" -o none || echo "(assignment may already exist)"

echo ""
az role assignment list --scope "$SCOPE" -o table
echo ""
echo "RBAC is eventually consistent - wait 1-5 minutes, then:"
echo "    terraform init -reconfigure"
