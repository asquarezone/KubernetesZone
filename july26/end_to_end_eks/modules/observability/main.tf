# ---------------------------------------------------------------------------
# Three-legged observability stack, mapped from the AKS lab:
#
#   Azure                          AWS
#   -----------------------------  -----------------------------------------
#   Log Analytics Workspace     -> CloudWatch Logs (log groups)
#   Azure Monitor Workspace     -> Amazon Managed Prometheus (AMP) workspace
#   Azure Managed Grafana       -> Amazon Managed Grafana (AMG) workspace
#   Action Group                -> SNS topic + subscriptions
#
# The one that behaves differently is Grafana. Azure Managed Grafana accepts
# an Entra ID role assignment and you are in. Amazon Managed Grafana REQUIRES
# an identity provider - AWS IAM Identity Center or SAML - configured at the
# ACCOUNT level before the workspace can be created. That is why
# enable_grafana defaults to false here and true in the AKS lab. See README
# Step 1.6.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Amazon Managed Prometheus - the Prometheus-compatible metric store.
# ---------------------------------------------------------------------------
resource "aws_prometheus_workspace" "this" {
  count = var.enable_managed_prometheus ? 1 : 0

  alias = "amp-${var.suffix}"
  tags  = var.tags
}

# ---------------------------------------------------------------------------
# The managed scraper. THIS is the analogue of the Azure DCR + DCRA - and,
# exactly as in the AKS lab, it is the association that actually switches
# collection on. An AMP workspace with no scraper collects precisely nothing
# and Grafana shows "no data".
#
# The scraper runs AWS-side (no agent pods of your own), discovers targets in
# your cluster, and writes into the AMP workspace.
# ---------------------------------------------------------------------------
resource "aws_prometheus_scraper" "this" {
  count = var.enable_managed_prometheus ? 1 : 0

  alias = "scraper-${var.suffix}"

  source {
    eks {
      cluster_arn = var.eks_cluster_arn
      subnet_ids  = var.private_subnet_ids
    }
  }

  destination {
    amp {
      workspace_arn = aws_prometheus_workspace.this[0].arn
    }
  }

  # Default AWS scrape config: kubelet, cadvisor, api server, and pods
  # carrying the standard prometheus.io/scrape annotations.
  scrape_configuration = <<-YAML
    global:
      scrape_interval: 30s
      external_labels:
        cluster: ${var.eks_cluster_name}
    scrape_configs:
      - job_name: kubernetes-apiservers
        kubernetes_sd_configs: [{ role: endpoints }]
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
            action: keep
            regex: default;kubernetes;https

      - job_name: kubernetes-nodes-cadvisor
        kubernetes_sd_configs: [{ role: node }]
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
        bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
        relabel_configs:
          - action: labelmap
            regex: __meta_kubernetes_node_label_(.+)
          - target_label: __address__
            replacement: kubernetes.default.svc:443
          - source_labels: [__meta_kubernetes_node_name]
            regex: (.+)
            target_label: __metrics_path__
            replacement: /api/v1/nodes/$${1}/proxy/metrics/cadvisor

      - job_name: kubernetes-pods
        kubernetes_sd_configs: [{ role: pod }]
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_namespace]
            target_label: namespace
          - source_labels: [__meta_kubernetes_pod_name]
            target_label: pod
  YAML

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Amazon Managed Grafana
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "grafana_assume" {
  count = var.enable_grafana ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "grafana" {
  count = var.enable_grafana ? 1 : 0

  name               = "role-grafana-${var.suffix}"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume[0].json
  tags               = var.tags
}

# Grafana's own identity must be able to READ the Prometheus store - the
# direct analogue of the "Monitoring Data Reader" role assignment on Azure.
data "aws_iam_policy_document" "grafana_amp_read" {
  count = var.enable_grafana ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "aps:QueryMetrics",
      "aps:GetLabels",
      "aps:GetSeries",
      "aps:GetMetricMetadata",
      "aps:ListWorkspaces",
      "aps:DescribeWorkspace",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "tag:GetResources",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "grafana_read" {
  count = var.enable_grafana ? 1 : 0

  name   = "grafana-datasource-read-${var.suffix}"
  role   = aws_iam_role.grafana[0].id
  policy = data.aws_iam_policy_document.grafana_amp_read[0].json
}

resource "aws_grafana_workspace" "this" {
  count = var.enable_grafana ? 1 : 0

  name                     = "graf-${var.suffix}"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"] # requires IAM Identity Center
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana[0].arn
  data_sources             = ["PROMETHEUS", "CLOUDWATCH"]
  grafana_version          = var.grafana_version
  tags                     = var.tags
}

# ---------------------------------------------------------------------------
# SNS topic - where alarms land. The analogue of an Azure action group.
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alarms" {
  name = "sns-alarms-${var.suffix}"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alert_email

  # NOTE: AWS sends a confirmation email that the recipient must click. Until
  # then this subscription sits in "PendingConfirmation" and delivers nothing.
  # Terraform cannot confirm it for you and will show it as created regardless.
}

# ---------------------------------------------------------------------------
# Application log group - Container Insights writes here.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/containerinsights/eks-${var.suffix}/application"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}
