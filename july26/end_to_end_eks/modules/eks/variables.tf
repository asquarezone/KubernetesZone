variable "suffix" { type = string }
variable "tags" { type = map(string) }
variable "kubernetes_version" { type = string }
variable "log_retention_days" { type = number }

variable "private_subnet_ids" { type = list(string) }
variable "public_subnet_ids" { type = list(string) }
variable "node_security_group_id" { type = string }

variable "system_node_instance_type" { type = string }
variable "system_node_min_count" { type = number }
variable "system_node_max_count" { type = number }
variable "user_node_instance_type" { type = string }
variable "user_node_min_count" { type = number }
variable "user_node_max_count" { type = number }
variable "system_pool_critical_addons_only" { type = bool }
variable "enable_spot_pool" { type = bool }
variable "enable_container_insights" { type = bool }

variable "spot_instance_types" {
  description = "Give Spot several shapes to choose from - one type is far more interruptible."
  type        = list(string)
  default     = ["t3.large", "t3a.large", "m5.large", "m5a.large"]
}

variable "service_ipv4_cidr" {
  description = "Kubernetes Service CIDR. MUST NOT overlap the VPC CIDR."
  type        = string
  default     = "172.20.0.0/16"
}

variable "public_access_cidrs" {
  description = "Who may reach the public API server endpoint. Narrow this for anything real."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
