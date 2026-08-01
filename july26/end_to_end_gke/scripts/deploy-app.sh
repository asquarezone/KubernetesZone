#!/usr/bin/env bash
# Deploys the AKS Store demo app plus this lab's HPA / ingress overlays.
set -euo pipefail

CLUSTER="$(terraform output -raw cluster_name)"
LOCATION="$(terraform output -raw cluster_location)"
PROJECT="$(terraform output -raw project_id)"

# GKE needs to know whether the location is a region or a zone. A zone has
# two dashes and a trailing letter (us-central1-a); a region has one.
if [[ "$LOCATION" =~ ^[a-z]+-[a-z0-9]+-[a-z]$ ]]; then
  gcloud container clusters get-credentials "$CLUSTER" --zone "$LOCATION" --project "$PROJECT"
else
  gcloud container clusters get-credentials "$CLUSTER" --region "$LOCATION" --project "$PROJECT"
fi

kubectl create namespace pets --dry-run=client -o yaml | kubectl apply -f -

echo "==> Deploying AKS Store demo (Azure-Samples/aks-store-demo)"
kubectl apply -n pets \
  -f https://raw.githubusercontent.com/Azure-Samples/aks-store-demo/main/aks-store-all-in-one.yaml

echo "==> Waiting for rollouts"
kubectl -n pets rollout status deploy/store-front   --timeout=5m || true
kubectl -n pets rollout status deploy/order-service --timeout=5m || true

echo "==> Applying lab overlays (HPA, PDB, ingress, scale-anchor)"
kubectl apply -f k8s/

echo ""
kubectl -n pets get pods,svc,hpa,ingress -o wide
echo ""
echo "NOTE: a GKE global HTTP load balancer takes 3-7 MINUTES to become"
echo "healthy. 'kubectl get ingress' showing no ADDRESS yet is normal."
