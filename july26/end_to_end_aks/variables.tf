variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "project" {
  description = "Short project name used in resource names."
  type        = string
  default     = "aksstore"
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
  description = "AKS control plane version. null = let Azure pick the default."
  type        = string
  default     = null
}

variable "system_node_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "system_node_min_count" {
  type    = number
  default = 1
}

variable "system_node_max_count" {
  type    = number
  default = 3
}

variable "user_node_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "user_node_min_count" {
  description = "Floor for the cluster autoscaler on the application pool."
  type        = number
  default     = 1
}

variable "user_node_max_count" {
  description = "Ceiling for the cluster autoscaler on the application pool."
  type        = number
  default     = 5
}

variable "max_pods_per_node" {
  type    = number
  default = 50
}

variable "system_pool_critical_addons_only" {
  description = <<-EOT
    When true the system pool is tainted CriticalAddonsOnly=true:NoSchedule so
    only AKS add-ons land there and all workload pods are forced onto the user
    pool. Production-correct, but students must remember the taint.
  EOT
  type        = bool
  default     = false
}

variable "enable_spot_pool" {
  description = "Add a Spot node pool to demonstrate cost-optimised burst capacity."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Features
# ---------------------------------------------------------------------------
variable "enable_acr" {
  type    = bool
  default = true
}

variable "enable_grafana" {
  description = "Deploy Azure Managed Grafana (adds cost - disable for short labs)."
  type        = bool
  default     = true
}

variable "grant_current_user_grafana_admin" {
  description = "Requires the caller to hold User Access Administrator / Owner."
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for the monitoring action group. Empty = no email receiver."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  type    = number
  default = 30
}
