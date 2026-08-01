variable "suffix" { type = string }
variable "project_id" { type = string }
variable "location" {
  description = "Region for a regional cluster, or a zone for a zonal one."
  type        = string
}
variable "labels" { type = map(string) }

variable "kubernetes_version" { type = string }
variable "release_channel" { type = string }
variable "deletion_protection" { type = bool }

variable "network_id" { type = string }
variable "subnet_id" { type = string }
variable "pods_range_name" { type = string }
variable "services_range_name" { type = string }
variable "master_ipv4_cidr" { type = string }
variable "private_nodes" { type = bool }
variable "max_pods_per_node" { type = number }

variable "authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "system_node_machine_type" { type = string }
variable "system_node_min_count" { type = number }
variable "system_node_max_count" { type = number }
variable "user_node_machine_type" { type = string }
variable "user_node_min_count" { type = number }
variable "user_node_max_count" { type = number }
variable "system_pool_critical_addons_only" { type = bool }
variable "enable_spot_pool" { type = bool }
variable "enable_managed_prometheus" { type = bool }
