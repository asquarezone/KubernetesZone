output "project_id" { value = var.project_id }
output "region" { value = var.region }

output "cluster_name" { value = module.gke.cluster_name }

output "cluster_location" {
  description = "A region for a regional cluster, a zone for a zonal one. get-credentials needs the right flag."
  value       = module.gke.location
}

output "network_name" { value = module.network.network_name }
output "subnet_name" { value = module.network.subnet_name }

output "artifact_registry_host" {
  value = var.enable_artifact_registry ? module.artifact_registry[0].registry_host : "artifact-registry-disabled"
}

output "workload_identity_pool" {
  description = "Needed for Workload Identity binding (the AKS OIDC issuer / EKS IRSA analogue)."
  value       = module.gke.workload_identity_pool
}

output "node_service_account_email" { value = module.gke.node_service_account_email }

output "get_credentials_command" {
  value = var.regional_cluster ? "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${var.region} --project ${var.project_id}" : "gcloud container clusters get-credentials ${module.gke.cluster_name} --zone ${var.zone} --project ${var.project_id}"
}

output "watch_autoscaler_command" {
  description = "GKE surfaces autoscaler decisions as cluster EVENTS, not as a configmap or pod logs."
  value       = "kubectl get events -A --field-selector reason=TriggeredScaleUp --watch"
}

output "monitoring_dashboard_url" {
  value = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
}

output "autoscaler_visibility_note" {
  description = "Where each cloud puts the autoscaler's reasoning - they are all different."
  value       = "AKS: control-plane diagnostics + cluster-autoscaler-status configmap | EKS: kubectl logs deploy/cluster-autoscaler | GKE: kubectl events + Cloud Logging (no CA pod exists)"
}
