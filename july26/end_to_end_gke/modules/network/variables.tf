variable "suffix" { type = string }
variable "region" { type = string }
variable "subnet_cidr" { type = string }
variable "pods_cidr" { type = string }
variable "services_cidr" { type = string }
variable "private_nodes" { type = bool }

variable "enable_flow_logs" {
  description = "VPC flow logs bill per GB. Off by default."
  type        = bool
  default     = false
}
