# Architecture (GCP / GKE)

```
                          Internet
                              |
              [ Global HTTP(S) Load Balancer ]   (GKE Ingress add-on)
                              |
                 routes to Network Endpoint Groups
                     (container-native, pod IPs)
                              |
   ---------------------------------------------------------------
   |                   GKE cluster (VPC-native)                   |
   |                                                              |
   |  system pool (1-2, autoscaled)   user pool (1-3, autoscaled) |
   |  - kube-dns                      - store-front (Vue)         |
   |  - metrics-server (managed)      - store-admin               |
   |  - gke-metrics-agent             - product-service (Rust)    |
   |  - fluentbit-gke                 - order-service (JS)        |
   |  - gmp collector (Prometheus)    - makeline-service (Go)     |
   |  - pdcsi / netd                  - virtual-customer/-worker  |
   |                                  - rabbitmq / documentdb     |
   ---------------------------------------------------------------
        |                    |                        |
   Cloud Logging     Managed Service for          Artifact
   (always on)          Prometheus                Registry
                             |
                   Cloud Monitoring dashboards
                   (or self-hosted Grafana)
                             |
              Alert policies -> Notification channel -> Email
```

Note what is **absent**: there is no cluster-autoscaler pod in that diagram.
On GKE the autoscaler lives in the control plane, exactly as on AKS.

## The autoscaling relay

```
  traffic rises
      |
      v
  metrics-server reports CPU
      |
      v
  HPA increases replicas            <-- pod-level
      |
      v
  scheduler cannot place pods --> Pending
      |
      v
  cluster autoscaler sees Pending --> resizes the managed instance group
      |
      v
  new node Ready --> pods scheduled                 <-- node-level
```

## Three CNI models, side by side

This is the single most useful cross-cloud comparison in the whole set.

| | Where pod IPs come from | Cost of scaling to N nodes |
|---|---|---|
| **AKS** (CNI Overlay) | a private overlay CIDR, off-VNet | N VNet IPs |
| **EKS** (VPC CNI) | the **node's own subnet**, shared with everything else | N × warm-pool IPs from that subnet |
| **GKE** (VPC-native) | a **dedicated secondary range** on the subnet | N × (max_pods rounded up to a power of 2) |

GKE sits in the middle: pod IPs are real and routable like AWS, but they come
from their own budget like Azure. The rounding is the trap — `max_pods_per_node
= 50` reserves a **/25 (128 addresses)** per node, not 50.

## What is genuinely different from AKS and EKS

| Concern | AKS | EKS | GKE |
|---|---|---|---|
| Cluster autoscaler | control-plane feature | **you install it** | control-plane feature, **per node pool** |
| Autoscaler reasoning | diagnostics + status configmap | `kubectl logs` on the CA pod | **`kubectl events`** + Cloud Logging |
| Extra autoscaler | — | Karpenter (optional) | **Node Auto-Provisioning** (creates pools) |
| Node counts | literal | literal | **per zone** on a regional cluster |
| Prometheus switch | DCR **association** | AMP **scraper** | one **boolean** on the cluster |
| Managed Grafana | yes | yes (needs an IdP) | **does not exist** |
| Logs | opt-in workspace + diagnostics | opt-in log types | **always on** |
| Registry auth | `AcrPull` role | node role policy | `artifactregistry.reader` on the node SA |
| Workload identity | OIDC federated credential | IRSA trust policy | **Workload Identity pool** |
| Blocks `destroy` | — | leftover LB ENIs | **`deletion_protection = true` by default** |

The three that bite hardest:

1. **Per-zone node counts.** Flip `regional_cluster = true` and your 5-node
   ceiling silently becomes 15.
2. **`deletion_protection` defaults to true** in the provider. `terraform
   destroy` fails outright until you set it false and re-apply.
3. **There is no managed Grafana.** Do not pretend otherwise.
