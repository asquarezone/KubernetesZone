# ===========================================================================
#  GKE cluster, node pools and Workload Identity.
#
#  WHERE GKE SITS BETWEEN ITS SIBLINGS
#  -----------------------------------
#  AKS: the cluster autoscaler is a control-plane feature (auto_scaler_profile)
#  EKS: it does not exist until you install it yourself
#  GKE: it is a control-plane feature AND it is per-node-pool AND there is a
#       second, cluster-level autoscaler called Node Auto-Provisioning that
#       can invent entirely new node pools on demand.
#
#  This lab uses per-node-pool autoscaling (the direct AKS analogue) and
#  leaves NAP off, because "a node pool you never declared just appeared" is
#  a poor first lesson.
# ===========================================================================

resource "google_service_account" "nodes" {
  account_id   = "sa-gke-nodes-${substr(replace(var.suffix, "_", "-"), 0, 20)}"
  display_name = "GKE node service account for ${var.suffix}"
}

# Least privilege for the node identity. The default Compute Engine service
# account is Editor on the whole project - which is why GKE hardening guides
# all start with "stop using the default service account".
resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader", # the GKE analogue of AcrPull
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# ---------------------------------------------------------------------------
# The cluster.
#
# NOTE ON THE DEFAULT NODE POOL: GKE insists on creating one. The universal
# pattern is to create it and immediately remove it, then manage real pools
# as separate resources - which is what remove_default_node_pool does. If you
# skip this you get an unmanaged pool that Terraform will not autoscale.
# ---------------------------------------------------------------------------
resource "google_container_cluster" "this" {
  name     = "gke-${var.suffix}"
  project  = var.project_id
  location = var.location

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network_id
  subnetwork = var.subnet_id

  min_master_version  = var.kubernetes_version
  deletion_protection = var.deletion_protection

  release_channel {
    channel = var.release_channel
  }

  # VPC-native. The secondary range NAMES must match modules/network.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  default_max_pods_per_node = var.max_pods_per_node

  private_cluster_config {
    enable_private_nodes    = var.private_nodes
    enable_private_endpoint = false # keep the public endpoint for lab access
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # -------------------------------------------------------------------------
  # WORKLOAD IDENTITY - the GKE analogue of AKS workload identity and EKS
  # IRSA. A Kubernetes ServiceAccount impersonates a Google service account
  # with no keys anywhere.
  # -------------------------------------------------------------------------
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # -------------------------------------------------------------------------
  # OBSERVABILITY
  #
  # This is where GKE is genuinely easier than its siblings. On AKS you wire
  # a DCE, a DCR and a DCR association. On EKS you create an AMP workspace
  # and a scraper. Here it is one boolean - and there is no separate
  # "association" to forget.
  # -------------------------------------------------------------------------
  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER",
      "STORAGE",
      "HPA",
      "POD",
      "DAEMONSET",
      "DEPLOYMENT",
      "STATEFULSET",
    ]

    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }
  }

  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER",
    ]
  }

  addons_config {
    http_load_balancing {
      disabled = false # the GKE Ingress controller
    }

    horizontal_pod_autoscaling {
      disabled = false
    }

    gcp_filestore_csi_driver_config {
      enabled = false
    }

    gcs_fuse_csi_driver_config {
      enabled = false
    }
  }

  # Gateway API - the successor to Ingress. Enabled so students can compare
  # the two models; k8s/03-ingress.yaml still uses classic Ingress.
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # Shielded nodes: verified boot and integrity monitoring.
  enable_shielded_nodes = true

  # Cost allocation surfaces per-namespace spend in billing export.
  cost_management_config {
    enabled = true
  }

  maintenance_policy {
    recurring_window {
      start_time = "2025-01-05T02:00:00Z"
      end_time   = "2025-01-05T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SU"
    }
  }

  resource_labels = var.labels

  lifecycle {
    ignore_changes = [
      # The release channel owns the version. Letting Terraform own it means
      # fighting GKE's auto-upgrade forever.
      min_master_version,
    ]
  }
}

# ---------------------------------------------------------------------------
# SYSTEM node pool
#
# REMEMBER: node_count and the autoscaling min/max are PER ZONE. On a regional
# cluster (3 zones) min_node_count = 1 gives you THREE nodes, not one. This
# catches nearly everyone the first time, and it is why the lab defaults to a
# zonal cluster.
# ---------------------------------------------------------------------------
resource "google_container_node_pool" "system" {
  name     = "system"
  project  = var.project_id
  location = var.location
  cluster  = google_container_cluster.this.name

  initial_node_count = var.system_node_min_count

  autoscaling {
    min_node_count = var.system_node_min_count
    max_node_count = var.system_node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = var.system_node_machine_type
    disk_size_gb    = 50
    disk_type       = "pd-balanced"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = {
      "nodepool-type" = "system"
      "workload"      = "platform"
    }

    dynamic "taint" {
      for_each = var.system_pool_critical_addons_only ? [1] : []
      content {
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    }

    workload_metadata_config {
      mode = "GKE_METADATA" # required for Workload Identity
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    resource_labels = var.labels
  }

  lifecycle {
    # node_count belongs to the autoscaler, not to Terraform.
    ignore_changes = [node_count, initial_node_count]
  }
}

# ---------------------------------------------------------------------------
# USER node pool - where the store microservices run.
# ---------------------------------------------------------------------------
resource "google_container_node_pool" "user" {
  name     = "user"
  project  = var.project_id
  location = var.location
  cluster  = google_container_cluster.this.name

  initial_node_count = var.user_node_min_count

  autoscaling {
    min_node_count = var.user_node_min_count
    max_node_count = var.user_node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = var.user_node_machine_type
    disk_size_gb    = 50
    disk_type       = "pd-balanced"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = {
      "nodepool-type" = "user"
      "workload"      = "apps"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    resource_labels = var.labels
  }

  lifecycle {
    ignore_changes = [node_count, initial_node_count]
  }
}

# ---------------------------------------------------------------------------
# Optional Spot pool. GCP Spot VMs have no bid price and no 24h cap (unlike
# the older "preemptible" VMs), but can still be reclaimed at any time.
# ---------------------------------------------------------------------------
resource "google_container_node_pool" "spot" {
  count = var.enable_spot_pool ? 1 : 0

  name     = "spot"
  project  = var.project_id
  location = var.location
  cluster  = google_container_cluster.this.name

  initial_node_count = 0

  autoscaling {
    min_node_count = 0
    max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.user_node_machine_type
    spot            = true
    disk_size_gb    = 50
    disk_type       = "pd-balanced"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = {
      "nodepool-type" = "spot"
    }

    taint {
      key    = "spot"
      value  = "true"
      effect = "NO_SCHEDULE"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    resource_labels = var.labels
  }

  lifecycle {
    ignore_changes = [node_count, initial_node_count]
  }
}
