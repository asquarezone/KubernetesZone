#!/usr/bin/env bash
# Deploys the AKS Store demo app plus this lab's HPA / ingress overlays.
#
# Yes, "AKS Store" on EKS. The app is plain Kubernetes with no Azure
# dependency, which is precisely why it is a good cross-cloud teaching
# subject: the SAME manifests behave differently underneath because the
# ingress, the CNI and the autoscaler are different.
set -euo pipefail

CLUSTER="$(terraform output -raw cluster_name)"
REGION="$(terraform output -raw region)"

aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"

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
echo "NOTE: the upstream manifest declares store-front and store-admin as"
echo "type: LoadBalancer, so AWS provisions Network Load Balancers for them"
echo "IN ADDITION to the ALB created by the Ingress objects. Billable."
