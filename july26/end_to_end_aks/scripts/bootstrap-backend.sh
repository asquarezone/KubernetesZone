#!/usr/bin/env bash
# Creates the remote state storage account. Run ONCE, before terraform init.
set -euo pipefail

LOC="${LOC:-eastus}"
RG="${RG:-rg-tfstate-aksstore}"
SA="sttfstate$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)"

az group create -n "$RG" -l "$LOC" -o none

az storage account create -n "$SA" -g "$RG" -l "$LOC" \
  --sku Standard_LRS --encryption-services blob \
  --min-tls-version TLS1_2 --allow-blob-public-access false -o none

az storage container create -n tfstate --account-name "$SA" --auth-mode login -o none

az storage account blob-service-properties update \
  --account-name "$SA" -g "$RG" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 7 -o none

echo ""
echo "  Backend ready."
echo "  Put this in backend.tf -> storage_account_name:"
echo ""
echo "      $SA"
echo ""
