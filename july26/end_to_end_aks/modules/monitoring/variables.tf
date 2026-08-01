variable "suffix"                     { type = string }
variable "location"                   { type = string }
variable "resource_group_name"        { type = string }
variable "tags"                       { type = map(string) }
variable "aks_cluster_id"             { type = string }
variable "monitor_workspace_id"       { type = string }
variable "log_analytics_workspace_id" { type = string }
variable "action_group_id"            { type = string }
