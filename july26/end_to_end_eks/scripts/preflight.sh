#!/usr/bin/env bash
# Checks the three things that kill this lab before Terraform runs:
# identity, permissions and EC2 vCPU quota.
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

echo "==> Identity"
aws sts get-caller-identity --output table

echo ""
echo "==> Region: $REGION"

echo ""
echo "==> On-Demand Standard vCPU quota (L-1216C47A)"
echo "    A brand-new AWS account often has only 5 vCPUs here, which is not"
echo "    enough for this lab. Each t3.large is 2 vCPU."
LIMIT="$(aws service-quotas get-service-quota \
  --service-code ec2 --quota-code L-1216C47A \
  --region "$REGION" --query 'Quota.Value' --output text 2>/dev/null || echo "unknown")"
echo "    Current limit: $LIMIT vCPUs"

if [[ "$LIMIT" != "unknown" ]]; then
  # bash has no floats; strip the decimal AWS returns (e.g. "32.0")
  LIMIT_INT="${LIMIT%%.*}"
  NEEDED=10
  if (( LIMIT_INT < NEEDED )); then
    echo ""
    echo "    *** TOO LOW. You need at least ${NEEDED} vCPUs for the default sizing"
    echo "    *** (2 system + 3 user nodes x 2 vCPU). Either request an increase:"
    echo "    ***   aws service-quotas request-service-quota-increase \\"
    echo "    ***     --service-code ec2 --quota-code L-1216C47A \\"
    echo "    ***     --desired-value 32 --region $REGION"
    echo "    *** or lower *_max_count in envs/dev.tfvars."
  else
    echo "    OK - enough for the default sizing (needs ${NEEDED})."
  fi
fi

echo ""
echo "==> Elastic IP quota (NAT gateways need one each)"
aws service-quotas get-service-quota \
  --service-code ec2 --quota-code L-0263D0A3 \
  --region "$REGION" --query 'Quota.Value' --output text 2>/dev/null || echo "unknown"

echo ""
echo "==> IAM Identity Center (required ONLY if enable_grafana = true)"
if aws sso-admin list-instances --region "$REGION" \
     --query 'Instances[0].InstanceArn' --output text 2>/dev/null | grep -q '^arn:'; then
  echo "    Enabled - you may set enable_grafana = true"
else
  echo "    NOT enabled - keep enable_grafana = false, or turn on IAM Identity"
  echo "    Center in the console first. Amazon Managed Grafana cannot be"
  echo "    created without an identity provider."
fi
