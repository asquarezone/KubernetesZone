output "resource_group_name" {
  description = "Resource group holding every lab resource."
  value       = module.network.resource_group_name
}

output "cluster_name" {
  value = module.aks.cluster_name
}

output "node_resource_group" {
  description = "AKS-managed RG containing the VMSS instances the autoscaler grows."
  value       = module.aks.node_resource_group
}

output "acr_login_server" {
  value = var.enable_acr ? module.acr[0].login_server : "acr-disabled"
}

output "grafana_endpoint" {
  value = module.observability.grafana_endpoint
}

output "oidc_issuer_url" {
  description = "Needed for workload identity federation (ai-service to Azure OpenAI)."
  value       = module.aks.oidc_issuer_url
}

output "get_credentials_command" {
  value = "az aks get-credentials -g ${module.network.resource_group_name} -n ${module.aks.cluster_name} --overwrite-existing"
}

output "watch_autoscaler_command" {
  value = "kubectl -n kube-system get configmap cluster-autoscaler-status -o yaml -w"
}
