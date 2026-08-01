# ---------------------------------------------------------------------------
# 1. MANAGED PROMETHEUS PIPELINE
#
#    AKS metrics agent --> Data Collection Endpoint --> Data Collection Rule
#                      --> Azure Monitor Workspace (Prometheus store)
#
#    The DCR *association* is what actually turns scraping on for the cluster.
# ---------------------------------------------------------------------------
resource "azurerm_monitor_data_collection_endpoint" "prom" {
  name                = "dce-prom-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"
  tags                = var.tags
}

resource "azurerm_monitor_data_collection_rule" "prom" {
  name                        = "dcr-prom-${var.suffix}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prom.id
  kind                        = "Linux"
  tags                        = var.tags

  destinations {
    monitor_account {
      monitor_account_id = var.monitor_workspace_id
      name               = "MonitoringAccount1"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount1"]
  }

  data_sources {
    prometheus_forwarder {
      streams = ["Microsoft-PrometheusMetrics"]
      name    = "PrometheusDataSource"
    }
  }

  description = "Managed Prometheus scrape pipeline for the AKS Store cluster"
}

resource "azurerm_monitor_data_collection_rule_association" "prom" {
  name                    = "dcra-prom-${var.suffix}"
  target_resource_id      = var.aks_cluster_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prom.id
  description             = "Associates the Prometheus DCR with the AKS cluster"
}

# ---------------------------------------------------------------------------
# 2. CONTROL PLANE DIAGNOSTIC LOGS
#
#    cluster-autoscaler is the category that matters for this project - it is
#    where "scale_up: setting group ... size to 3" messages appear.
# ---------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag-aks-${var.suffix}"
  target_resource_id         = var.aks_cluster_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "kube-apiserver" }
  enabled_log { category = "kube-controller-manager" }
  enabled_log { category = "kube-scheduler" }
  enabled_log { category = "cluster-autoscaler" }
  enabled_log { category = "kube-audit-admin" }
  enabled_log { category = "guard" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ---------------------------------------------------------------------------
# 3. ALERT RULES
# ---------------------------------------------------------------------------
resource "azurerm_monitor_metric_alert" "node_cpu" {
  name                = "alert-node-cpu-${var.suffix}"
  resource_group_name = var.resource_group_name
  scopes              = [var.aks_cluster_id]
  description         = "Average node CPU above 80% for 5 minutes - autoscaler should be adding nodes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = var.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "node_memory" {
  name                = "alert-node-memory-${var.suffix}"
  resource_group_name = var.resource_group_name
  scopes              = [var.aks_cluster_id]
  description         = "Average node working set memory above 80% for 5 minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_memory_working_set_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = var.action_group_id
  }
}

resource "azurerm_monitor_metric_alert" "not_ready_nodes" {
  name                = "alert-nodes-notready-${var.suffix}"
  resource_group_name = var.resource_group_name
  scopes              = [var.aks_cluster_id]
  description         = "One or more nodes reporting NotReady."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "kube_node_status_condition"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0

    dimension {
      name     = "condition"
      operator = "Include"
      values   = ["Ready"]
    }
    dimension {
      name     = "status"
      operator = "Include"
      values   = ["false", "unknown"]
    }
  }

  action {
    action_group_id = var.action_group_id
  }
}

# ---------------------------------------------------------------------------
# 4. LOG-BASED ALERT - pods stuck in a crash loop
# ---------------------------------------------------------------------------
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "pod_restarts" {
  name                = "alert-pod-restarts-${var.suffix}"
  resource_group_name = var.resource_group_name
  location            = var.location
  scopes              = [var.log_analytics_workspace_id]
  severity            = 2
  evaluation_frequency = "PT10M"
  window_duration      = "PT15M"
  description          = "A pod in the pets namespace restarted more than 5 times."
  tags                 = var.tags

  criteria {
    query                   = <<-KQL
      KubePodInventory
      | where Namespace == "pets"
      | summarize Restarts = max(PodRestartCount) by Name, Namespace
      | where Restarts > 5
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluations_to_back_off        = 1
    }
  }

  action {
    action_groups = [var.action_group_id]
  }
}
