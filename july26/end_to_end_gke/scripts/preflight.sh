#!/usr/bin/env bash
# Checks what kills this lab before Terraform runs: auth, billing, APIs, quota.
set -euo pipefail

PROJECT="${GOOGLE_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${GOOGLE_REGION:-us-central1}"

echo "==> Identity"
gcloud auth list --filter=status:ACTIVE --format="table(account)" 2>/dev/null

echo ""
echo "==> Application Default Credentials"
if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "    ADC present - Terraform can authenticate."
else
  echo "    *** MISSING. Terraform uses ADC, NOT your gcloud login."
  echo "    *** Run: gcloud auth application-default login"
fi

echo ""
echo "==> Project: ${PROJECT:-<unset>}"
[[ -z "$PROJECT" ]] && { echo "    *** No project set: gcloud config set project <id>"; exit 1; }

echo ""
echo "==> Billing"
BILLING="$(gcloud beta billing projects describe "$PROJECT" \
  --format='value(billingEnabled)' 2>/dev/null || echo "unknown")"
if [[ "$BILLING" == "True" ]]; then
  echo "    Enabled."
else
  echo "    *** NOT ENABLED (or no permission to check). GKE cannot be created"
  echo "    *** in a project without billing. This is the #1 GCP lab blocker."
fi

echo ""
echo "==> CPU quota in $REGION"
echo "    Each e2-standard-2 is 2 vCPU. Default sizing needs 10."
gcloud compute regions describe "$REGION" --project "$PROJECT" \
  --format="table(quotas.filter('metric:CPUS').metric,
                  quotas.filter('metric:CPUS').usage,
                  quotas.filter('metric:CPUS').limit)" 2>/dev/null \
  || echo "    (could not read quota - check manually in the console)"

echo ""
echo "==> In-use IP address quota (each node takes one internal IP)"
gcloud compute project-info describe --project "$PROJECT" \
  --format="value(quotas.filter('metric:IN_USE_ADDRESSES').limit)" 2>/dev/null \
  || echo "    unknown"

echo ""
echo "==> APIs (terraform enables these, but check for org policy blocks)"
for api in container.googleapis.com compute.googleapis.com \
           artifactregistry.googleapis.com monitoring.googleapis.com \
           logging.googleapis.com; do
  STATE="$(gcloud services list --enabled --project "$PROJECT" \
    --filter="config.name=$api" --format='value(config.name)' 2>/dev/null || true)"
  printf "    %-42s %s\n" "$api" "${STATE:+ENABLED}${STATE:-not yet}"
done

echo ""
echo "==> Reminder: GCP has NO managed Grafana."
echo "    enable_grafana = true self-hosts it in-cluster via install-grafana.sh."
