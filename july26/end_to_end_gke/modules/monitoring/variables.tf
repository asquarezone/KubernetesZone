variable "suffix" { type = string }
variable "project_id" { type = string }
variable "labels" { type = map(string) }
variable "cluster_name" { type = string }
variable "notification_channels" { type = list(string) }
