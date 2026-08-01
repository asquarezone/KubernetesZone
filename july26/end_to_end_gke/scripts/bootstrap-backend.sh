#!/usr/bin/env bash
# Creates the remote state bucket. Run ONCE, before terraform init.
set -euo pipefail

PROJECT="${GOOGLE_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${GOOGLE_REGION:-us-central1}"
BUCKET="tfstate-gkestore-${PROJECT}-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"

gcloud storage buckets create "gs://${BUCKET}" \
  --project "$PROJECT" \
  --location "$REGION" \
  --uniform-bucket-level-access \
  --public-access-prevention

# Versioning gives you a way back from a bad apply. GCS locking is built in -
# there is no DynamoDB-equivalent table to create.
gcloud storage buckets update "gs://${BUCKET}" --versioning

echo ""
echo "  Backend ready."
echo "  Put this in backend.tf -> bucket:"
echo ""
echo "      $BUCKET"
echo ""
echo "  NOTE: GCS state locking is automatic. Nothing else to configure."
