# ---------------------------------------------------------------------------
# Three-legged observability stack:
#   1. Log Analytics Workspace  -> logs      (Container Insights, control plane)
#   2. Azure Monitor Workspace  -> metrics   (Managed Prometheus, PromQL)
#   3. Azure Managed Grafana    -> dashboards over both
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

# Azure Monitor Workspace = the Prometheus-compatible metrics store
resource "azurerm_monitor_workspace" "this" {
  name                = "amw-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_dashboard_grafana" "this" {
  count                             = var.enable_grafana ? 1 : 0
  name                              = "graf-${var.suffix}"
  resource_group_name               = var.resource_group_name
  location                          = var.location
  grafana_major_version             = "11"
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = false
  public_network_access_enabled     = true
  tags                              = var.tags

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.this.id
  }
}

# Grafana's managed identity must be able to read the Prometheus metrics store.
resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  count                = var.enable_grafana ? 1 : 0
  scope                = azurerm_monitor_workspace.this.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.this[0].identity[0].principal_id
}

# Let the human running Terraform actually log in to Grafana.
resource "azurerm_role_assignment" "grafana_admin" {
  count                = var.enable_grafana && var.grant_current_user_grafana_admin ? 1 : 0
  scope                = azurerm_dashboard_grafana.this[0].id
  role_definition_name = "Grafana Admin"
  principal_id         = var.current_user_object_id
}

# ---------------------------------------------------------------------------
# Action group - where alerts land
# ---------------------------------------------------------------------------
resource "azurerm_monitor_action_group" "this" {
  name                = "ag-${var.suffix}"
  resource_group_name = var.resource_group_name
  short_name          = "aksstore"
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.alert_email == "" ? [] : [var.alert_email]
    content {
      name                    = "primary-oncall"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}
