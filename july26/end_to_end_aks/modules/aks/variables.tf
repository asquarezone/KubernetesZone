variable "suffix"                    { type = string }
variable "location"                  { type = string }
variable "resource_group_name"       { type = string }
variable "tags"                      { type = map(string) }
variable "kubernetes_version"        { type = string }
variable "system_subnet_id"          { type = string }
variable "user_subnet_id"            { type = string }
variable "log_analytics_workspace_id" { type = string }

variable "system_node_vm_size"       { type = string }
variable "system_node_min_count"     { type = number }
variable "system_node_max_count"     { type = number }
variable "user_node_vm_size"         { type = string }
variable "user_node_min_count"       { type = number }
variable "user_node_max_count"       { type = number }
variable "max_pods_per_node"         { type = number }
variable "system_pool_critical_addons_only" { type = bool }
variable "enable_spot_pool"          { type = bool }

variable "pod_cidr" {
  type    = string
  default = "192.168.0.0/16"
}
variable "service_cidr" {
  type    = string
  default = "172.16.0.0/16"
}
variable "dns_service_ip" {
  type    = string
  default = "172.16.0.10"
}
