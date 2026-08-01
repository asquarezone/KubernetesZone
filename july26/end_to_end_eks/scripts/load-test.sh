#!/usr/bin/env bash
# Generates HTTP load against store-front so the HPA scales pods on CPU.
#
# IMPORTANT - read this before you expect nodes to appear:
#
#   Upstream aks-store-demo sets `requests.cpu: 1m` on store-front. The HPA
#   therefore hits maxReplicas almost instantly (any traffic exceeds 50% of
#   1m), but 30 replicas x 1m = 30m of *requested* CPU, which fits on one node
#   with room to spare. The cluster autoscaler reads REQUESTS, not usage, so
#   this load alone will NOT add nodes.
#
#   This script demonstrates the HPA half of the relay. For the node-level
#   half use the deterministic path:
#
#       kubectl -n pets scale deploy/scale-anchor --replicas=3
#
#   That is the lesson, not a bug: usage does not scale nodes, requests do.
set -euo pipefail

PARALLELISM="${1:-10}"
DURATION="${2:-10m}"
CONCURRENCY="${3:-50}"

kubectl -n pets delete job loadgen --ignore-not-found

# NOTE: `kubectl scale` does NOT support Jobs (only deployment / replicaset /
# replicationcontroller / statefulset), so parallelism must be set at creation
# time rather than patched afterwards.
kubectl -n pets apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: loadgen
spec:
  parallelism: ${PARALLELISM}
  completions: ${PARALLELISM}
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: hey
          image: williamyeh/hey
          args: ["-z", "${DURATION}", "-c", "${CONCURRENCY}", "http://store-front:80/"]
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
EOF

echo ""
echo "Started ${PARALLELISM} load generator pods for ${DURATION}."
echo "Watch three things in three terminals:"
echo "  1) kubectl -n pets get hpa -w"
echo "  2) kubectl get nodes -w"
echo "  3) kubectl -n kube-system logs -f deploy/cluster-autoscaler"
