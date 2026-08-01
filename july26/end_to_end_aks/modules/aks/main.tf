resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-aks-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.suffix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "aks-${var.suffix}"
  kubernetes_version  = var.kubernetes_version
  node_resource_group = "rg-${var.suffix}-nodes"
  sku_tier            = "Free" # switch to "Standard" for an SLA-backed cluster
  tags                = var.tags

  # -------------------------------------------------------------------------
  # SYSTEM node pool - runs CoreDNS, metrics-server, the monitoring agents
  # and (critically) the cluster autoscaler itself.
  # -------------------------------------------------------------------------
  default_node_pool {
    name                        = "system"
    vm_size                     = var.system_node_vm_size
    vnet_subnet_id              = var.system_subnet_id
    max_pods                    = var.max_pods_per_node
    os_disk_size_gb             = 64
    os_disk_type                = "Managed"
    zones                       = ["1", "2", "3"]
    only_critical_addons_enabled = var.system_pool_critical_addons_only
    temporary_name_for_rotation = "systemtmp"

    auto_scaling_enabled = true
    min_count            = var.system_node_min_count
    max_count            = var.system_node_max_count

    upgrade_settings {
      max_surge = "33%"
    }

    node_labels = {
      "nodepool-type" = "system"
      "workload"      = "platform"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  # -------------------------------------------------------------------------
  # Networking - Azure CNI Overlay. Pods get IPs from pod_cidr, NOT the VNet,
  # so autoscaling never exhausts the subnet.
  # -------------------------------------------------------------------------
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  # -------------------------------------------------------------------------
  # CLUSTER AUTOSCALER TUNING - the heart of this project.
  #
  #   expander = "least-waste"   pick the pool that leaves the least idle CPU/RAM
  #   scale_down_unneeded = 5m   how long a node must look idle before removal
  #   scale_down_utilization_threshold = 0.5
  #                              a node under 50% requested utilisation is a
  #                              scale-down candidate
  #   scan_interval = 10s        how often the autoscaler re-evaluates
  #
  # Lab values are deliberately aggressive so students SEE scale-down inside a
  # class. Production would use 10-15m to avoid thrashing.
  # -------------------------------------------------------------------------
  auto_scaler_profile {
    balance_similar_node_groups      = true
    expander                         = "least-waste"
    max_graceful_termination_sec     = "600"
    max_node_provisioning_time       = "15m"
    max_unready_nodes                = 3
    max_unready_percentage           = 45
    new_pod_scale_up_delay           = "0s"
    scale_down_delay_after_add       = "5m"
    scale_down_delay_after_delete    = "10s"
    scale_down_delay_after_failure   = "3m"
    scan_interval                    = "10s"
    scale_down_unneeded              = "5m"
    scale_down_unready               = "20m"
    scale_down_utilization_threshold = "0.5"
    empty_bulk_delete_max            = "10"
    skip_nodes_with_local_storage    = false
    skip_nodes_with_system_pods      = true
  }

  # KEDA (event-driven autoscaling) + VPA - feeds work to the autoscaler
  workload_autoscaler_profile {
    keda_enabled                    = true
    vertical_pod_autoscaler_enabled = true
  }

  # Container Insights -> Log Analytics (logs + inventory)
  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  # Azure Monitor Managed Prometheus scraping agent
  monitor_metrics {
    annotations_allowed = null
    labels_allowed      = null
  }

  # Security / platform features
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  azure_policy_enabled      = true
  local_account_disabled    = false # keep true in production
  image_cleaner_enabled     = true
  image_cleaner_interval_hours = 48
  role_based_access_control_enabled = true

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # Managed NGINX ingress controller (used in Step 7)
  web_app_routing {
    dns_zone_ids = []
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+05:30"
  }

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count, # owned by the autoscaler, not Terraform
      kubernetes_version,              # owned by the auto-upgrade channel
    ]
  }
}

# ---------------------------------------------------------------------------
# USER node pool - where the AKS Store microservices actually run.
# This is the pool students will watch scale 1 -> 5 under load.
# ---------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_node_vm_size
  vnet_subnet_id        = var.user_subnet_id
  mode                  = "User"
  os_type               = "Linux"
  os_disk_size_gb       = 64
  max_pods              = var.max_pods_per_node
  zones                 = ["1", "2", "3"]
  tags                  = var.tags

  auto_scaling_enabled = true
  min_count            = var.user_node_min_count
  max_count            = var.user_node_max_count

  upgrade_settings {
    max_surge = "33%"
  }

  node_labels = {
    "nodepool-type" = "user"
    "workload"      = "apps"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

# ---------------------------------------------------------------------------
# Optional Spot pool - burst capacity at up to 90% discount.
# Tainted so only pods that explicitly tolerate eviction land here.
# ---------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster_node_pool" "spot" {
  count                 = var.enable_spot_pool ? 1 : 0
  name                  = "spot"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_node_vm_size
  vnet_subnet_id        = var.user_subnet_id
  mode                  = "User"
  priority              = "Spot"
  eviction_policy       = "Delete"
  spot_max_price        = -1 # -1 = pay up to the on-demand price
  max_pods              = var.max_pods_per_node
  tags                  = var.tags

  auto_scaling_enabled = true
  min_count            = 0
  max_count            = 3

  node_labels = {
    "kubernetes.azure.com/scalesetpriority" = "spot"
    "nodepool-type"                         = "spot"
  }

  node_taints = ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]

  lifecycle {
    ignore_changes = [node_count]
  }
}
