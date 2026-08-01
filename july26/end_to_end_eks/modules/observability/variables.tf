variable "suffix" { type = string }
variable "tags" { type = map(string) }
variable "log_retention_days" { type = number }
variable "alert_email" { type = string }

variable "enable_grafana" { type = bool }
variable "enable_managed_prometheus" { type = bool }

variable "eks_cluster_arn" { type = string }
variable "eks_cluster_name" { type = string }
variable "private_subnet_ids" { type = list(string) }

# AWS retires Grafana versions the same way Azure does. Check the current
# supported list with:
#   aws grafana list-versions
variable "grafana_version" {
  type    = string
  default = "10.4"
}
