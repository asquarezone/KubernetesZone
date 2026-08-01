# Architecture (AWS / EKS)

```
                          Internet
                              |
                  [ Application Load Balancer ]   (AWS LB Controller)
                              |
                    routes DIRECTLY to pod IPs
                              |
   ---------------------------------------------------------------
   |                    EKS cluster (VPC CNI)                     |
   |                                                              |
   |  system pool (1-2, autoscaled)   user pool (1-3, autoscaled) |
   |  - CoreDNS                       - store-front (Vue)         |
   |  - metrics-server                - store-admin               |
   |  - cluster-autoscaler  <-- YOU   - product-service (Rust)    |
   |  - cloudwatch-agent              - order-service (JS)        |
   |  - fluent-bit                    - makeline-service (Go)     |
   |  - aws-load-balancer-controller  - virtual-customer/-worker  |
   |                                  - rabbitmq / documentdb     |
   ---------------------------------------------------------------
        |                    |                        |
   CloudWatch Logs   Amazon Managed Prometheus      Amazon ECR
   (control plane,      (AMP + managed scraper)
    Container
    Insights)                 |
        \___________ Amazon Managed Grafana _______/
                              |
                    Alarms -> SNS topic -> Email
```

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
  cluster autoscaler sees Pending --> SetDesiredCapacity on the ASG
      |
      v
  new node Ready --> pods scheduled                 <-- node-level
```

Scale-down runs the reverse, gated by:
- `--scale-down-unneeded-time` (5m in this lab)
- `--scale-down-utilization-threshold` (0.5)
- PodDisruptionBudgets
- `--skip-nodes-with-system-pods` / `--skip-nodes-with-local-storage`

## What is genuinely different from AKS

| Concern | AKS | EKS |
|---|---|---|
| Cluster autoscaler | control-plane feature, `auto_scaler_profile` | a Deployment **you install and own** |
| Autoscaler logs | control-plane diagnostics -> Log Analytics | `kubectl logs deploy/cluster-autoscaler` |
| Node group discovery | implicit | **ASG tags** `k8s.io/cluster-autoscaler/*` |
| Pod networking | CNI Overlay — pods off-VNet by default | VPC CNI — **every pod takes a real VPC IP** |
| Ingress | managed NGINX, one shared IP | ALB per Ingress group, routes to pod IPs |
| Workload identity | OIDC + federated credential | OIDC + **IRSA** trust policy |
| Registry auth | `AcrPull` role assignment | node role policy `...ContainerRegistryReadOnly` |
| Prometheus switch | DCR **association** (DCRA) | AMP **scraper** |
| Grafana access | Entra role assignment | **requires IAM Identity Center / SAML** |
| Log-based alert | KQL query *is* the alert | metric filter **then** alarm |

The two that surprise people most:

1. **The VPC CNI consumes real subnet IPs per pod.** On AKS with CNI Overlay,
   scaling to 5 nodes costs 5 VNet IPs. Here it costs 5 nodes' worth of
   *pre-allocated pod IPs*. Undersize the private subnets and nodes join but
   pods never get addresses.
2. **Nothing autoscales until you install the autoscaler.** A perfectly
   healthy EKS cluster with correct tags and IAM will sit there with Pending
   pods forever if you skipped `scripts/install-autoscaler.sh`.
