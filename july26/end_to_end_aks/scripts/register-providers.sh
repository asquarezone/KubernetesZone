#!/usr/bin/env bash
set -euo pipefail
PROVIDERS=(
  Microsoft.ContainerService
  Microsoft.OperationalInsights
  Microsoft.Monitor
  Microsoft.Dashboard
  Microsoft.ContainerRegistry
  Microsoft.Insights
  Microsoft.AlertsManagement
  Microsoft.KubernetesConfiguration
)
for p in "${PROVIDERS[@]}"; do
  echo "Registering $p ..."
  az provider register --namespace "$p" -o none
done
echo ""
for p in "${PROVIDERS[@]}"; do
  printf "%-40s %s\n" "$p" "$(az provider show -n "$p" --query registrationState -o tsv)"
done
