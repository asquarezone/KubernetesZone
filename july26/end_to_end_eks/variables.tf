variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short project name used in resource names."
  type        = string
  default     = "ekstore"
}

variable "env" {
  description = "Environment name (dev / test / prod)."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Tag value - who owns this lab environment."
  type        = string
  default     = "learning-thoughts-lab"
}

# ---------------------------------------------------------------------------
# Cluster sizing / autoscaling
# ---------------------------------------------------------------------------
variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.31"
}

variable "system_node_instance_type" {
  description = <<-EOT
    Instance type for the system pool. t3.large is 2 vCPU / 8 GiB. Check your
    On-Demand Standard vCPU quota before changing this - see the README.
  EOT
  type        = string
  default     = "t3.large"
}

variable "system_node_min_count" {
  type    = number
  default = 1
}

variable "system_node_max_count" {
  type    = number
  default = 2
}

variable "user_node_instance_type" {
  type    = string
  default = "t3.large"
}

variable "user_node_min_count" {
  description = "Floor for the cluster autoscaler on the application pool."
  type        = number
  default     = 1
}

variable "user_node_max_count" {
  description = "Ceiling for the cluster autoscaler on the application pool."
  type        = number
  default     = 3
}

variable "system_pool_critical_addons_only" {
  description = <<-EOT
    When true the system pool is tainted CriticalAddonsOnly=true:NoSchedule so
    only add-ons land there and all workload pods are forced onto the user
    pool. Production-correct, but students must remember the taint.
  EOT
  type        = bool
  default     = false
}

variable "enable_spot_pool" {
  description = "Add a Spot node group to demonstrate cost-optimised burst capacity."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "az_count" {
  description = "How many Availability Zones to spread across. EKS requires >= 2."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2
    error_message = "EKS requires subnets in at least two Availability Zones."
  }
}

variable "single_nat_gateway" {
  description = <<-EOT
    true  = one NAT gateway shared by all AZs (cheap, single point of failure)
    false = one NAT gateway per AZ (production-correct, ~3x the cost)
    A NAT gateway costs money per hour AND per GB. This is the single largest
    line item in this lab after the nodes.
  EOT
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Features
# ---------------------------------------------------------------------------
variable "enable_ecr" {
  type    = bool
  default = true
}

variable "enable_grafana" {
  description = <<-EOT
    Deploy Amazon Managed Grafana. REQUIRES AWS IAM Identity Center to be
    enabled in this account/region first - see README Step 1.6. Set to false
    for short labs or if you cannot enable Identity Center.
  EOT
  type        = bool
  default     = false
}

variable "enable_managed_prometheus" {
  description = "Deploy Amazon Managed Prometheus + its managed scraper."
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address subscribed to the SNS alarm topic. Empty = no subscription."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "additional_admin_principal_arn" {
  description = <<-EOT
    Optional second IAM principal (user or role ARN) to grant cluster-admin
    via an EKS access entry. The principal that RUNS terraform is already an
    admin via bootstrap_cluster_creator_admin_permissions. Set this when the
    cluster is built by a pipeline role but humans need kubectl access.
  EOT
  type        = string
  default     = ""
}
