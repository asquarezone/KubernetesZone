#!/usr/bin/env bash
# Installs the AWS Load Balancer Controller - the EKS analogue of the AKS
# managed NGINX (web_app_routing) add-on.
#
# Terraform created the IAM ROLE; the controller's IAM POLICY is long and AWS
# revises it, so we fetch the current official document rather than ship a
# stale copy.
set -euo pipefail

CLUSTER="$(terraform output -raw cluster_name)"
REGION="$(terraform output -raw region)"
VPC_ID="$(terraform output -raw vpc_id)"
ROLE_ARN="$(terraform output -raw lb_controller_role_arn)"
ROLE_NAME="${ROLE_ARN##*/}"
LBC_VERSION="${LBC_VERSION:-v2.8.2}"

command -v helm >/dev/null || {
  echo "helm is required for this step. Install it: https://helm.sh/docs/intro/install/" >&2
  exit 1
}

aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"

echo "==> Fetching the official IAM policy for ${LBC_VERSION}"
curl -fsSL -o /tmp/lbc-policy.json \
  "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${LBC_VERSION}/docs/install/iam_policy.json"

POLICY_NAME="AWSLoadBalancerControllerIAMPolicy-${CLUSTER}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
POLICY_ARN="arn:aws:iam::${ACCOUNT}:policy/${POLICY_NAME}"

if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  echo "==> Policy already exists: $POLICY_ARN"
else
  echo "==> Creating policy $POLICY_NAME"
  aws iam create-policy --policy-name "$POLICY_NAME" \
    --policy-document file:///tmp/lbc-policy.json >/dev/null
fi

echo "==> Attaching policy to $ROLE_NAME"
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"

echo "==> Installing the controller via Helm"
helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo update >/dev/null

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set "clusterName=$CLUSTER" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$ROLE_ARN" \
  --set "region=$REGION" \
  --set "vpcId=$VPC_ID" \
  --wait

echo ""
echo "Done. The controller watches for Ingress objects with"
echo "ingressClassName: alb and provisions real ALBs for them."
