output "log_analytics_workspace_id" { value = azurerm_log_analytics_workspace.this.id }
output "monitor_workspace_id"       { value = azurerm_monitor_workspace.this.id }
output "action_group_id"            { value = azurerm_monitor_action_group.this.id }
output "grafana_endpoint" {
  value = var.enable_grafana ? azurerm_dashboard_grafana.this[0].endpoint : "grafana-disabled"
}
