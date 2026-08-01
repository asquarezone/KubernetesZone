# ---------------------------------------------------------------------------
# Observability on GCP, and the one honest gap in the three-cloud set.
#
#   Azure                          GCP
#   -----------------------------  -----------------------------------------
#   Log Analytics Workspace     -> Cloud Logging (built in, no resource)
#   Azure Monitor Workspace     -> Managed Service for Prometheus (a cluster
#                                  flag, not a separate workspace resource)
#   Azure Managed Grafana       -> *** DOES NOT EXIST ***
#   Action Group                -> Notification channel
#   Metric alert                -> Alert policy
#
# GCP has no managed Grafana offering. Your three options:
#
#   1. Cloud Monitoring dashboards - native, free, no Grafana at all. This
#      module creates one (below).
#   2. Self-hosted Grafana in the cluster, reading Managed Prometheus through
#      the datasource syncer. scripts/install-grafana.sh does this.
#   3. Grafana Cloud - a paid third-party SaaS.
#
# Do not paper over this with a resource that "looks like" the Azure one.
# The lesson is that cloud parity is never exact, and pretending otherwise
# is how students get surprised in an interview.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Log bucket retention.
#
# Cloud Logging always exists - there is nothing to provision to "turn logs
# on". What you CAN control is how long the _Default bucket keeps them, which
# is the actual cost lever.
# ---------------------------------------------------------------------------
resource "google_logging_project_bucket_config" "default" {
  project        = var.project_id
  location       = "global"
  bucket_id      = "_Default"
  retention_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# A dedicated log bucket + sink for the cluster, so lab logs are separable
# from everything else in the project.
# ---------------------------------------------------------------------------
resource "google_logging_project_bucket_config" "lab" {
  project        = var.project_id
  location       = var.region
  bucket_id      = "log-${var.suffix}"
  description    = "GKE Store lab logs"
  retention_days = var.log_retention_days
}

resource "google_logging_project_sink" "lab" {
  name        = "sink-${var.suffix}"
  project     = var.project_id
  destination = "logging.googleapis.com/${google_logging_project_bucket_config.lab.id}"

  filter = <<-FILTER
    resource.type="k8s_container"
    resource.labels.cluster_name="${var.cluster_name}"
  FILTER

  unique_writer_identity = true
}

# ---------------------------------------------------------------------------
# Notification channel - the analogue of an Azure action group / SNS topic.
# ---------------------------------------------------------------------------
resource "google_monitoring_notification_channel" "email" {
  count = var.alert_email == "" ? 0 : 1

  project      = var.project_id
  display_name = "oncall-${var.suffix}"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

# ---------------------------------------------------------------------------
# A Cloud Monitoring dashboard.
#
# This is the "no Grafana needed" path. It is genuinely good for GKE - the
# built-in GKE dashboards are better than anything you would build by hand -
# but it is not Grafana and it does not speak PromQL in the same places.
# ---------------------------------------------------------------------------
resource "google_monitoring_dashboard" "cluster" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "GKE Store Lab - ${var.suffix}"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Node count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"kubernetes.io/node/cpu/allocatable_cores\" resource.type=\"k8s_node\" resource.label.\"cluster_name\"=\"${var.cluster_name}\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_COUNT"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          xPos   = 6
          width  = 6
          height = 4
          widget = {
            title = "Pod CPU usage - pets namespace"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"kubernetes.io/container/cpu/core_usage_time\" resource.type=\"k8s_container\" resource.label.\"cluster_name\"=\"${var.cluster_name}\" resource.label.\"namespace_name\"=\"pets\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.\"pod_name\""]
                    }
                  }
                }
              }]
            }
          }
        },
        {
          yPos   = 4
          width  = 12
          height = 4
          widget = {
            title = "Node CPU allocatable utilisation"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"kubernetes.io/node/cpu/allocatable_utilization\" resource.type=\"k8s_node\" resource.label.\"cluster_name\"=\"${var.cluster_name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
            }
          }
        },
      ]
    }
  })
}
