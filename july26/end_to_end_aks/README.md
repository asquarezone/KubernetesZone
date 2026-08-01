# Pets, Pods & Pipelines
### End-to-end AKS Store deployment on Azure Kubernetes Service with Terraform

A complete, classroom-ready infrastructure project. Students provision a
production-shaped AKS cluster with Terraform, deploy the
[Azure-Samples/aks-store-demo](https://github.com/Azure-Samples/aks-store-demo)
microservices app, then drive it hard enough to watch the **cluster autoscaler**
add and remove nodes under full observability.

---

## What gets built

| Layer | Resources |
|---|---|
| Network | VNet `10.10.0.0/16`, 3 subnets, NSG with LB-probe + web rules |
| Registry | ACR (RBAC only, no admin user) + `AcrPull` to the kubelet identity |
| Cluster | AKS, Azure CNI **Overlay**, user-assigned identity, 3 availability zones |
| Autoscaling | Cluster autoscaler on **both** pools + tuned `auto_scaler_profile` + KEDA + VPA |
| Security | Workload identity, OIDC issuer, Azure Policy, image cleaner, CSI secrets store |
| Ingress | AKS managed NGINX (`web_app_routing`) |
| Monitoring | Container Insights, Azure Monitor **managed Prometheus** (DCE/DCR/DCRA), Managed Grafana, control-plane diagnostics incl. `cluster-autoscaler` logs, 3 metric alerts + 1 KQL log alert |

---

## Repository layout

```
aks-store-infra/
├── backend.tf              remote state (azurerm)
├── providers.tf            hashicorp/azurerm 4.x + hashicorp/random ONLY
├── variables.tf            every knob, documented
├── locals.tf               naming + tagging convention
├── main.tf                 module wiring + role assignments
├── outputs.tf              handy commands as outputs
├── envs/dev.tfvars         lab defaults
├── modules/
│   ├── network/            RG, VNet, subnets, NSG
│   ├── acr/                container registry
│   ├── observability/      LAW, Azure Monitor Workspace, Grafana, action group
│   ├── aks/                cluster + node pools + autoscaler profile
│   └── monitoring/         DCE/DCR/DCRA, diagnostics, alert rules
├── k8s/                    HPA, PDB, Ingress, scale-anchor demo
└── scripts/                bootstrap, deploy, load test
```

---

## Quick start

```bash
# 0. Prereqs
./scripts/register-providers.sh

# 1. Remote state (run once, then paste the SA name into backend.tf)
./scripts/bootstrap-backend.sh
./scripts/grant-backend-access.sh <storage-account-name>   # data-plane RBAC

# 2. Configure
cp envs/dev.example.tfvars envs/dev.tfvars
#    edit: subscription_id, owner, alert_email

# 3. Provision (~12-15 min)
terraform init
terraform fmt -recursive
terraform validate
terraform plan  -var-file=envs/dev.tfvars -out=tfplan
terraform apply tfplan

# 4. Deploy the app
./scripts/deploy-app.sh

# 5. Get the public URL
kubectl -n app-routing-system get svc nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

---

## Proving the cluster autoscaler works

The relay: **load -> HPA adds pods -> pods go Pending -> CA adds nodes.**
Pending pods are the *only* trigger. Nothing else scales a node pool.

```bash
# Terminal 1
kubectl get nodes -w

# Terminal 2
kubectl -n pets get hpa -w

# Terminal 3 - the autoscaler's own scoreboard
kubectl -n kube-system get configmap cluster-autoscaler-status -o yaml

# Trigger it - deterministic version (1 vCPU per pod)
kubectl -n pets scale deploy/scale-anchor --replicas=6
kubectl -n pets get pods -l app=scale-anchor -o wide

# Trigger it - realistic version (HTTP load)
./scripts/load-test.sh
```

Scale-down takes about 5-10 minutes with the lab settings
(`scale_down_unneeded = 5m`, `scale_down_utilization_threshold = 0.5`).

Read the control-plane view in Log Analytics:

```kusto
AzureDiagnostics
| where Category == "cluster-autoscaler"
| project TimeGenerated, log_s
| order by TimeGenerated desc
```

---

## Monitoring checklist

1. **Container Insights** — Azure Portal > cluster > Monitoring > Insights.
2. **Managed Prometheus** — Grafana endpoint from `terraform output grafana_endpoint`.
   Import dashboard IDs `20179` (Kubernetes / Compute Resources / Cluster) or use
   the pre-provisioned Azure Managed Prometheus folder.
3. **PromQL to try**
   ```promql
   sum(rate(container_cpu_usage_seconds_total{namespace="pets"}[5m])) by (pod)
   kube_pod_status_phase{namespace="pets", phase="Pending"}
   count(kube_node_info)
   ```
4. **Alerts** — three metric alerts + one KQL crash-loop alert wired to the
   action group. Set `alert_email` in tfvars to receive them.

---

## Teardown (do this every session — the cluster costs money)

```bash
kubectl delete ns pets --ignore-not-found
terraform destroy -var-file=envs/dev.tfvars
```

Verify nothing survived:
```bash
az group list --query "[?starts_with(name,'rg-aksstore')].name" -o tsv
```

---

## Common failures and what they teach

| Symptom | Root cause | Lesson |
|---|---|---|
| `InvalidCIDRNotation` / overlap error | pod_cidr overlaps VNet | CIDR planning is not optional |
| Pods stay Pending, node count never grows | pool already at `max_count`, or no resource *requests* set | CA reads requests, not usage |
| Nodes never scale down | a pod with local storage / no PDB / kube-system pod on the node | `skip_nodes_with_*` flags |
| `ImagePullBackOff` from ACR | `AcrPull` role not propagated yet | RBAC is eventually consistent |
| Grafana shows "no data" | DCRA missing — Prometheus was never turned on | the association is the switch |
| State lock error | two students, one backend | why remote state exists |
| `403 AuthorizationPermissionMismatch` on `init` | Contributor is control-plane; blobs need `Storage Blob Data Contributor` | Azure RBAC has two planes |

---

## Provider policy

This project uses **only HashiCorp-published providers**: `hashicorp/azurerm`
and `hashicorp/random`. No `Azure/azapi`, no `Azure/azuread`. Everything the
lab needs — including managed Prometheus data collection rules and Managed
Grafana — is supported natively in `azurerm` 4.x.

Why it matters in a classroom: many corporate networks allow-list the Terraform
Registry by namespace. A single-namespace dependency graph installs cleanly
behind a proxy and keeps `terraform init` reproducible.

```bash
terraform providers   # should list exactly two, both hashicorp/
```

---

## Notes

- `azurerm` v4 renamed several arguments (`enable_auto_scaling` -> `auto_scaling_enabled`).
  This project uses the v4 names throughout.
- `node_count` is in `ignore_changes` on both pools — it belongs to the
  autoscaler, and letting Terraform own it causes permanent drift.
- `sku_tier = "Free"` has no uptime SLA. Use `Standard` for anything real.
- The AKS Store `ai-service` needs Azure OpenAI; it is optional and the rest of
  the app runs without it. Workload identity is pre-enabled for it via
  `oidc_issuer_url`.
