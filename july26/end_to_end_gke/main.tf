# ===========================================================================
#  GKE Store - End to End Infrastructure
#  Learning Thoughts | "Pets, Pods & Pipelines" (GCP edition)
#
#  Order of construction:
#    apis -> network -> artifact registry -> gke -> observability -> monitoring
#
#  Note that observability comes AFTER the cluster here, as on AWS, because
#  the log sink and the alert policies filter on the cluster name. On Azure
#  it came first, because the cluster referenced the workspace id.
# ===========================================================================

# ---------------------------------------------------------------------------
# Enable the APIs this lab needs.
#
# GCP is the only one of the three clouds where a brand-new project has
# essentially nothing switched on. This is the analogue of the AKS
# register-providers.sh script, except it is Terraform-managed because the
# dependency is real: creating a cluster before container.googleapis.com is
# enabled fails outright.
#
# disable_on_destroy = false on purpose. Turning an API off during destroy can
# break OTHER things in a shared project, and it is almost never what you want.
# ---------------------------------------------------------------------------
resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "servicenetworking.googleapis.com",
    "stackdriver.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}

module "network" {
  source = "./modules/network"

  suffix        = local.suffix
  region        = var.region
  subnet_cidr   = var.subnet_cidr
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr
  private_nodes = var.private_nodes

  depends_on = [google_project_service.required]
}

module "artifact_registry" {
  count  = var.enable_artifact_registry ? 1 : 0
  source = "./modules/artifact_registry"

  suffix     = local.suffix
  project_id = var.project_id
  region     = var.region
  labels     = local.labels

  depends_on = [google_project_service.required]
}

module "gke" {
  source = "./modules/gke"

  suffix     = local.suffix
  project_id = var.project_id
  # Regional cluster -> location is a region and nodes spread over its zones.
  # Zonal cluster    -> location is a single zone.
  location = var.regional_cluster ? var.region : var.zone
  labels   = local.labels

  kubernetes_version  = var.kubernetes_version
  release_channel     = var.release_channel
  deletion_protection = var.deletion_protection

  network_id          = module.network.network_id
  subnet_id           = module.network.subnet_id
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  master_ipv4_cidr    = var.master_ipv4_cidr
  private_nodes       = var.private_nodes
  max_pods_per_node   = var.max_pods_per_node
  authorized_networks = var.authorized_networks

  system_node_machine_type         = var.system_node_machine_type
  system_node_min_count            = var.system_node_min_count
  system_node_max_count            = var.system_node_max_count
  user_node_machine_type           = var.user_node_machine_type
  user_node_min_count              = var.user_node_min_count
  user_node_max_count              = var.user_node_max_count
  system_pool_critical_addons_only = var.system_pool_critical_addons_only
  enable_spot_pool                 = var.enable_spot_pool
  enable_managed_prometheus        = var.enable_managed_prometheus

  depends_on = [google_project_service.required]
}

module "observability" {
  source = "./modules/observability"

  suffix             = local.suffix
  project_id         = var.project_id
  region             = var.region
  labels             = local.labels
  log_retention_days = var.log_retention_days
  alert_email        = var.alert_email
  cluster_name       = module.gke.cluster_name
}

module "monitoring" {
  source = "./modules/monitoring"

  suffix                = local.suffix
  project_id            = var.project_id
  labels                = local.labels
  cluster_name          = module.gke.cluster_name
  notification_channels = module.observability.notification_channels
}
