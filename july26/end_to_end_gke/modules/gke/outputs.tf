output "cluster_name" { value = google_container_cluster.this.name }
output "cluster_id" { value = google_container_cluster.this.id }
output "location" { value = google_container_cluster.this.location }
output "endpoint" { value = google_container_cluster.this.endpoint }

output "workload_identity_pool" {
  description = "The analogue of the AKS OIDC issuer / EKS IRSA provider."
  value       = "${var.project_id}.svc.id.goog"
}

output "node_service_account_email" { value = google_service_account.nodes.email }

output "ca_certificate" {
  value     = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive = true
}
