#!/usr/bin/env bash
# Deploys the AKS Store demo app plus the lab's HPA / ingress overlays.
set -euo pipefail

RG="$(terraform output -raw resource_group_name)"
CLUSTER="$(terraform output -raw cluster_name)"

az aks get-credentials -g "$RG" -n "$CLUSTER" --overwrite-existing

kubectl create namespace pets --dry-run=client -o yaml | kubectl apply -f -

echo "==> Deploying AKS Store demo (Azure-Samples/aks-store-demo)"
kubectl apply -n pets \
  -f https://raw.githubusercontent.com/Azure-Samples/aks-store-demo/main/aks-store-all-in-one.yaml

echo "==> Waiting for rollouts"
kubectl -n pets rollout status deploy/store-front   --timeout=5m || true
kubectl -n pets rollout status deploy/order-service --timeout=5m || true

echo "==> Applying lab overlays (HPA, PDB, ingress)"
kubectl apply -f k8s/

echo ""
kubectl -n pets get pods,svc,hpa -o wide
