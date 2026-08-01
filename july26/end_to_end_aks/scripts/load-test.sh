#!/usr/bin/env bash
# Generates enough load to force HPA -> Pending pods -> cluster autoscaler.
set -euo pipefail
REPLICAS="${1:-30}"

kubectl -n pets delete job loadgen --ignore-not-found
kubectl -n pets create job loadgen --image=williamyeh/hey -- \
  hey -z 10m -c 100 http://store-front:80/

kubectl -n pets scale job/loadgen --replicas="$REPLICAS" 2>/dev/null || true

echo "Watch three things in three terminals:"
echo "  1) kubectl -n pets get hpa -w"
echo "  2) kubectl get nodes -w"
echo "  3) kubectl -n kube-system get cm cluster-autoscaler-status -o yaml | less"
