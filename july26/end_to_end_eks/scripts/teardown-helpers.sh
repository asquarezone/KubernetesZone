#!/usr/bin/env bash
# Things that must happen BEFORE terraform destroy, and the usual suspects
# that survive it.
#
# Run this, then `terraform destroy`.
set -euo pipefail

echo "==> Deleting the pets namespace"
echo "    This releases the LoadBalancer Services (NLBs) and the ALB created"
echo "    by the Ingress objects. Terraform did not create them - the AWS Load"
echo "    Balancer Controller did - so terraform destroy will NOT remove them,"
echo "    and a leftover ALB holds ENIs that block VPC deletion."
kubectl delete ns pets --ignore-not-found --timeout=5m || true

echo ""
echo "==> Removing PodDisruptionBudgets that can block a node drain"
echo "    A PDB with ALLOWED DISRUPTIONS = 0 will stall node group deletion"
echo "    indefinitely. Check for stragglers:"
kubectl get pdb -A --no-headers 2>/dev/null | awk '$5==0 {print "    BLOCKING: "$1"/"$2}' || true

echo ""
echo "==> Waiting for load balancers to disappear"
for i in $(seq 1 30); do
  COUNT="$(aws elbv2 describe-load-balancers \
    --query "length(LoadBalancers[?VpcId=='$(terraform output -raw vpc_id)'])" \
    --output text 2>/dev/null || echo 0)"
  [[ "$COUNT" == "0" ]] && { echo "    All load balancers gone."; break; }
  echo "    $COUNT still present, waiting..."
  sleep 10
done

echo ""
echo "Now run: terraform destroy -var-file=envs/dev.tfvars"
