variable "suffix" { type = string }
variable "tags" { type = map(string) }
variable "eks_cluster_name" { type = string }
variable "sns_topic_arn" { type = string }
variable "app_log_group_name" { type = string }
