# ---------------------------------------------------------------------------
# ALERT POLICIES
#
# The GCP shape of the AKS metric alerts. Three differences worth teaching:
#
#   1. There is no "metric namespace" to name - the metric TYPE string is
#      fully qualified (kubernetes.io/node/...).
#   2. The filter language is Google's monitoring filter syntax, not KQL and
#      not a CloudWatch dimension map.
#   3. A log-based alert needs a log-based METRIC first, exactly as CloudWatch
#      needs a metric filter. Only Azure lets the query itself be the alert.
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "node_cpu" {
  project      = var.project_id
  display_name = "alert-node-cpu-${var.suffix}"
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = "Average node CPU allocatable utilisation above 80% for 5 minutes - the autoscaler should be adding nodes."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Node CPU > 80%"

    condition_threshold {
      filter = join(" ", [
        "metric.type=\"kubernetes.io/node/cpu/allocatable_utilization\"",
        "resource.type=\"k8s_node\"",
        "resource.label.\"cluster_name\"=\"${var.cluster_name}\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.notification_channels
  user_labels           = var.labels
}

resource "google_monitoring_alert_policy" "node_memory" {
  project      = var.project_id
  display_name = "alert-node-memory-${var.suffix}"
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = "Average node memory allocatable utilisation above 80% for 5 minutes."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Node memory > 80%"

    condition_threshold {
      filter = join(" ", [
        "metric.type=\"kubernetes.io/node/memory/allocatable_utilization\"",
        "resource.type=\"k8s_node\"",
        "resource.label.\"cluster_name\"=\"${var.cluster_name}\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.notification_channels
  user_labels           = var.labels
}

# ---------------------------------------------------------------------------
# Node not ready.
#
# kubernetes.io/node/status_condition carries the condition as a metric label,
# so the filter selects Ready=false rather than counting a separate metric.
# ---------------------------------------------------------------------------
resource "google_monitoring_alert_policy" "node_not_ready" {
  project      = var.project_id
  display_name = "alert-nodes-notready-${var.suffix}"
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = "One or more nodes reporting NotReady."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Node not Ready"

    condition_threshold {
      filter = join(" ", [
        "metric.type=\"kubernetes.io/node/status_condition\"",
        "resource.type=\"k8s_node\"",
        "resource.label.\"cluster_name\"=\"${var.cluster_name}\"",
        "metric.label.\"condition\"=\"Ready\"",
        "metric.label.\"status\"=\"false\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
        cross_series_reducer = "REDUCE_MAX"
      }
    }
  }

  notification_channels = var.notification_channels
  user_labels           = var.labels
}

# ---------------------------------------------------------------------------
# LOG-BASED ALERT - pods stuck in a crash loop.
#
# Two pieces, exactly like CloudWatch:
#   1. a log-based metric that counts matching log entries
#   2. an alert policy on that metric
# ---------------------------------------------------------------------------
resource "google_logging_metric" "crashloop" {
  project = var.project_id
  name    = "crashloop-${var.suffix}"

  filter = <<-FILTER
    resource.type="k8s_pod"
    resource.labels.cluster_name="${var.cluster_name}"
    resource.labels.namespace_name="pets"
    jsonPayload.reason="BackOff"
  FILTER

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "crashloop" {
  project      = var.project_id
  display_name = "alert-pod-crashloop-${var.suffix}"
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = "A pod in the pets namespace is crash-looping."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "CrashLoopBackOff events > 5 in 15m"

    condition_threshold {
      filter = join(" ", [
        "metric.type=\"logging.googleapis.com/user/${google_logging_metric.crashloop.name}\"",
        "resource.type=\"k8s_pod\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "0s"

      aggregations {
        alignment_period   = "900s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = var.notification_channels
  user_labels           = var.labels
}
