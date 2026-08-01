variable "suffix" { type = string }
variable "project_id" { type = string }
variable "region" { type = string }
variable "labels" { type = map(string) }
variable "log_retention_days" { type = number }
variable "alert_email" { type = string }
variable "cluster_name" { type = string }
