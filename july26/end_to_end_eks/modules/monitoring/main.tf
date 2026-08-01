# ---------------------------------------------------------------------------
# ALARMS
#
# These read Container Insights metrics, which the amazon-cloudwatch-
# observability add-on publishes into the "ContainerInsights" namespace.
# If that add-on is disabled the alarms will sit in INSUFFICIENT_DATA
# forever - which is itself a useful thing for students to see and diagnose.
#
# Mapping from the AKS lab:
#   node_cpu_usage_percentage            -> node_cpu_utilization
#   node_memory_working_set_percentage   -> node_memory_utilization
#   kube_node_status_condition (NotReady)-> cluster_failed_node_count
#   KQL crash-loop log alert             -> metric filter + alarm (below)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "node_cpu" {
  alarm_name          = "alarm-node-cpu-${var.suffix}"
  alarm_description   = "Average node CPU above 80% for 5 minutes - the autoscaler should be adding nodes."
  namespace           = "ContainerInsights"
  metric_name         = "node_cpu_utilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "node_memory" {
  alarm_name          = "alarm-node-memory-${var.suffix}"
  alarm_description   = "Average node memory utilisation above 80% for 5 minutes."
  namespace           = "ContainerInsights"
  metric_name         = "node_memory_utilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "failed_nodes" {
  alarm_name          = "alarm-nodes-failed-${var.suffix}"
  alarm_description   = "One or more nodes reporting NotReady."
  namespace           = "ContainerInsights"
  metric_name         = "cluster_failed_node_count"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  period              = 300
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  alarm_actions = [var.sns_topic_arn]
  tags          = var.tags
}

# ---------------------------------------------------------------------------
# LOG-BASED ALARM - pods stuck in a crash loop.
#
# This is the AWS shape of the AKS KQL alert. CloudWatch has no "run a query
# on a schedule and alarm on the row count" primitive, so it takes two pieces:
#
#   1. a metric filter that turns matching log lines into a metric
#   2. an alarm on that metric
#
# Teaching point: on Azure the query IS the alert. On AWS you must first
# manufacture a metric, because CloudWatch alarms only understand metrics.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "crashloop" {
  name           = "filter-crashloop-${var.suffix}"
  log_group_name = var.app_log_group_name

  # Container Insights application logs are JSON.
  pattern = "{ $.kubernetes.namespace_name = \"pets\" && $.log = %CrashLoopBackOff% }"

  metric_transformation {
    name          = "PodCrashLoopCount"
    namespace     = "EKSLab/${var.suffix}"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "crashloop" {
  alarm_name          = "alarm-pod-crashloop-${var.suffix}"
  alarm_description   = "A pod in the pets namespace is crash-looping."
  namespace           = "EKSLab/${var.suffix}"
  metric_name         = aws_cloudwatch_log_metric_filter.crashloop.metric_transformation[0].name
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  period              = 900
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.sns_topic_arn]
  tags          = var.tags
}
