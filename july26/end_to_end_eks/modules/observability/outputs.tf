output "amp_workspace_id" {
  value = var.enable_managed_prometheus ? aws_prometheus_workspace.this[0].id : ""
}
output "amp_workspace_arn" {
  value = var.enable_managed_prometheus ? aws_prometheus_workspace.this[0].arn : ""
}
output "amp_query_endpoint" {
  description = "Point Grafana's Prometheus data source at this."
  value       = var.enable_managed_prometheus ? aws_prometheus_workspace.this[0].prometheus_endpoint : "amp-disabled"
}
output "grafana_endpoint" {
  value = var.enable_grafana ? "https://${aws_grafana_workspace.this[0].endpoint}" : "grafana-disabled"
}
output "sns_topic_arn" { value = aws_sns_topic.alarms.arn }
output "app_log_group_name" { value = aws_cloudwatch_log_group.app.name }
