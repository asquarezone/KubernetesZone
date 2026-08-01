output "alert_policy_names" {
  value = [
    google_monitoring_alert_policy.node_cpu.display_name,
    google_monitoring_alert_policy.node_memory.display_name,
    google_monitoring_alert_policy.node_not_ready.display_name,
    google_monitoring_alert_policy.crashloop.display_name,
  ]
}
output "crashloop_metric_name" { value = google_logging_metric.crashloop.name }
