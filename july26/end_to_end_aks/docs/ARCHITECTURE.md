# Architecture

```
                          Internet
                              |
                     [ Azure Load Balancer ]
                              |
                 +------------------------+
                 |  Managed NGINX Ingress |   (web_app_routing add-on)
                 +------------------------+
                              |
   ---------------------------------------------------------------
   |                    AKS cluster (CNI Overlay)                 |
   |                                                              |
   |  system pool (1-3, autoscaled)   user pool (1-5, autoscaled) |
   |  - CoreDNS                       - store-front (Vue)         |
   |  - metrics-server                - store-admin               |
   |  - ama-metrics (Prometheus)      - product-service (Rust)    |
   |  - ama-logs (Container Insights) - order-service (JS)        |
   |  - cluster autoscaler            - makeline-service (Go)     |
   |                                  - ai-service (Python, opt)  |
   |                                  - rabbitmq / mongodb        |
   ---------------------------------------------------------------
        |                    |                        |
   Log Analytics     Azure Monitor Workspace     Azure Container
   (logs, KQL,        (Prometheus metrics)         Registry
    autoscaler                |
    diagnostics)              |
        \___________ Azure Managed Grafana ________/
                              |
                        Alerts -> Action Group -> Email
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
  cluster autoscaler sees Pending --> scales the VMSS   <-- node-level
      |
      v
  new node Ready --> pods scheduled
```

Scale-down runs the reverse, gated by:
- `scale_down_unneeded` (5m in this lab)
- `scale_down_utilization_threshold` (0.5)
- PodDisruptionBudgets
- `skip_nodes_with_system_pods` / `skip_nodes_with_local_storage`
