# ===========================================================================
#  AKS Store - End to End Infrastructure
#  Learning Thoughts | "Pets, Pods & Pipelines"
#
#  Order of construction (Terraform works this out from the references):
#    network -> observability -> acr -> aks -> monitoring -> role bindings
# ===========================================================================

module "network" {
  source   = "./modules/network"
  suffix   = local.suffix
  location = var.location
  tags     = local.tags
}

module "observability" {
  source                           = "./modules/observability"
  suffix                           = local.suffix
  location                         = var.location
  resource_group_name              = module.network.resource_group_name
  tags                             = local.tags
  log_retention_days               = var.log_retention_days
  enable_grafana                   = var.enable_grafana
  grant_current_user_grafana_admin = var.grant_current_user_grafana_admin
  current_user_object_id           = data.azurerm_client_config.current.object_id
  alert_email                      = var.alert_email
}

module "acr" {
  count               = var.enable_acr ? 1 : 0
  source              = "./modules/acr"
  suffix              = local.suffix
  location            = var.location
  resource_group_name = module.network.resource_group_name
  tags                = local.tags
}

module "aks" {
  source                     = "./modules/aks"
  suffix                     = local.suffix
  location                   = var.location
  resource_group_name        = module.network.resource_group_name
  tags                       = local.tags
  kubernetes_version         = var.kubernetes_version
  system_subnet_id           = module.network.system_subnet_id
  user_subnet_id             = module.network.user_subnet_id
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  system_node_vm_size              = var.system_node_vm_size
  system_node_min_count            = var.system_node_min_count
  system_node_max_count            = var.system_node_max_count
  user_node_vm_size                = var.user_node_vm_size
  user_node_min_count              = var.user_node_min_count
  user_node_max_count              = var.user_node_max_count
  max_pods_per_node                = var.max_pods_per_node
  system_pool_critical_addons_only = var.system_pool_critical_addons_only
  enable_spot_pool                 = var.enable_spot_pool
}

module "monitoring" {
  source                     = "./modules/monitoring"
  suffix                     = local.suffix
  location                   = var.location
  resource_group_name        = module.network.resource_group_name
  tags                       = local.tags
  aks_cluster_id             = module.aks.cluster_id
  monitor_workspace_id       = module.observability.monitor_workspace_id
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id
  action_group_id            = module.observability.action_group_id
}

# ---------------------------------------------------------------------------
# Role bindings
# ---------------------------------------------------------------------------

# Let the kubelet pull images from ACR without any imagePullSecret.
resource "azurerm_role_assignment" "acr_pull" {
  count                            = var.enable_acr ? 1 : 0
  scope                            = module.acr[0].id
  role_definition_name             = "AcrPull"
  principal_id                     = module.aks.kubelet_identity_object_id
  skip_service_principal_aad_check = true
}

# Let the AKS control plane identity manage the pre-created subnets.
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = module.network.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = module.aks.cluster_identity_principal_id
}

# Give the Terraform caller cluster-admin over the AKS data plane.
resource "azurerm_role_assignment" "aks_rbac_admin" {
  scope                = module.aks.cluster_id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
