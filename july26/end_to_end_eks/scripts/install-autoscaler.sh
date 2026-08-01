#!/usr/bin/env bash
# Installs the Kubernetes Cluster Autoscaler into kube-system.
#
# WHY THIS IS A SCRIPT AND NOT TERRAFORM
# --------------------------------------
# On AKS the cluster autoscaler is a control-plane feature you switch on with
# auto_scaler_profile. On EKS it does not exist until you install it. Doing
# that from Terraform needs the kubernetes or helm provider, configured from
# an output of a cluster that does not exist during the first plan - the
# classic chicken-and-egg failure. So: Terraform builds the IAM role and the
# ASG discovery tags; this script installs the workload.
set -euo pipefail

CLUSTER="$(terraform output -raw cluster_name)"
REGION="$(terraform output -raw region)"
ROLE_ARN="$(terraform output -raw autoscaler_role_arn)"
CA_VERSION="${CA_VERSION:-v1.31.0}"

echo "==> Cluster:  $CLUSTER"
echo "==> Region:   $REGION"
echo "==> Role ARN: $ROLE_ARN"

aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"

echo "==> Applying upstream cluster-autoscaler manifest ($CA_VERSION)"
kubectl apply -f \
  "https://raw.githubusercontent.com/kubernetes/autoscaler/cluster-autoscaler-${CA_VERSION#v}/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml"

echo "==> Binding the ServiceAccount to the IAM role (IRSA)"
kubectl -n kube-system annotate serviceaccount cluster-autoscaler \
  "eks.amazonaws.com/role-arn=$ROLE_ARN" --overwrite

echo "==> Pointing auto-discovery at THIS cluster and tuning for the lab"
# The upstream manifest ships a placeholder cluster name. These flags are the
# direct equivalents of the AKS auto_scaler_profile block.
kubectl -n kube-system patch deployment cluster-autoscaler --type json -p "$(cat <<JSON
[
  {"op":"replace","path":"/spec/template/spec/containers/0/command","value":[
    "./cluster-autoscaler",
    "--v=4",
    "--stderrthreshold=info",
    "--cloud-provider=aws",
    "--skip-nodes-with-local-storage=false",
    "--skip-nodes-with-system-pods=true",
    "--expander=least-waste",
    "--balance-similar-node-groups=true",
    "--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/${CLUSTER}",
    "--scan-interval=10s",
    "--scale-down-unneeded-time=5m",
    "--scale-down-delay-after-add=5m",
    "--scale-down-delay-after-delete=10s",
    "--scale-down-delay-after-failure=3m",
    "--scale-down-utilization-threshold=0.5",
    "--max-graceful-termination-sec=600",
    "--max-node-provision-time=15m",
    "--new-pod-scale-up-delay=0s"
  ]}
]
JSON
)"

# Stops the autoscaler evicting itself during a scale-down.
kubectl -n kube-system patch deployment cluster-autoscaler -p \
  '{"spec":{"template":{"metadata":{"annotations":{"cluster-autoscaler.kubernetes.io/safe-to-evict":"false"}}}}}'

echo "==> Waiting for rollout"
kubectl -n kube-system rollout status deploy/cluster-autoscaler --timeout=3m

echo ""
echo "Done. Watch it think with:"
echo "    kubectl -n kube-system logs -f deploy/cluster-autoscaler"
echo ""
echo "Confirm it found your node groups (should list 'system' and 'user'):"
echo "    kubectl -n kube-system logs deploy/cluster-autoscaler | grep -i 'node group'"
