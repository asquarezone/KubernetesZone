#!/usr/bin/env bash
# Self-hosts Grafana in the cluster, because GCP HAS NO MANAGED GRAFANA.
#
# This is the one place the three labs genuinely diverge:
#   Azure -> Azure Managed Grafana, a first-class resource
#   AWS   -> Amazon Managed Grafana, a first-class resource (needs an IdP)
#   GCP   -> nothing. You self-host, use Cloud Monitoring, or pay Grafana Cloud.
#
# The datasource syncer is what lets in-cluster Grafana query Google Cloud
# Managed Service for Prometheus: it mints credentials and keeps the
# datasource pointed at the right Monitoring endpoint.
set -euo pipefail

PROJECT="$(terraform output -raw project_id)"
NAMESPACE="${NAMESPACE:-monitoring}"

command -v helm >/dev/null || {
  echo "helm is required. Install: https://helm.sh/docs/intro/install/" >&2
  exit 1
}

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing Grafana"
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null

helm upgrade --install grafana grafana/grafana \
  -n "$NAMESPACE" \
  --set persistence.enabled=false \
  --set adminPassword=admin \
  --set service.type=ClusterIP \
  --wait

echo ""
echo "==> Deploying the Managed Prometheus datasource syncer"
kubectl -n "$NAMESPACE" apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: datasource-syncer
spec:
  schedule: "*/30 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: datasource-syncer
              image: gke.gcr.io/prometheus-engine/datasource-syncer:v0.13.0-gke.0
              args:
                - "--datasource-uids=prometheus"
                - "--grafana-api-endpoint=http://grafana.${NAMESPACE}.svc:80"
                - "--grafana-api-token=\$(GRAFANA_TOKEN)"
                - "--project-id=${PROJECT}"
              env:
                - name: GRAFANA_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: grafana-token
                      key: token
                      optional: true
EOF

echo ""
echo "Grafana installed. Reach it with:"
echo "    kubectl -n $NAMESPACE port-forward svc/grafana 3000:80"
echo "    open http://localhost:3000   (admin / admin)"
echo ""
echo "NOTE: the syncer needs a Grafana service-account token in a secret named"
echo "'grafana-token'. Create one in the Grafana UI, then:"
echo "    kubectl -n $NAMESPACE create secret generic grafana-token --from-literal=token=<TOKEN>"
echo ""
echo "If you would rather not run Grafana at all, use Cloud Monitoring:"
echo "    terraform output monitoring_dashboard_url"
