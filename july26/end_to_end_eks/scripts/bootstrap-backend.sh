#!/usr/bin/env bash
# Creates the remote state bucket. Run ONCE, before terraform init.
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="tfstate-ekstore-${ACCOUNT}-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"

# us-east-1 is the one region where create-bucket must NOT get a
# LocationConstraint. Everywhere else it is mandatory. This asymmetry has
# broken more bootstrap scripts than any other line in AWS.
if [[ "$REGION" == "us-east-1" ]]; then
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
fi

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'

echo ""
echo "  Backend ready."
echo "  Put this in backend.tf -> bucket:"
echo ""
echo "      $BUCKET"
echo ""
echo "  Also confirm backend.tf region matches: $REGION"
echo ""
echo "  NOTE: this uses S3 native locking (use_lockfile) - no DynamoDB table"
echo "  is needed. That requires Terraform >= 1.10."
