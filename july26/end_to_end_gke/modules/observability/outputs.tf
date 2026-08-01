output "notification_channel_id" {
  value = var.alert_email == "" ? "" : google_monitoring_notification_channel.email[0].id
}
output "notification_channels" {
  description = "List form, for alert policies."
  value       = var.alert_email == "" ? [] : [google_monitoring_notification_channel.email[0].id]
}
output "log_bucket_id" { value = google_logging_project_bucket_config.lab.id }
output "dashboard_id" { value = google_monitoring_dashboard.cluster.id }
