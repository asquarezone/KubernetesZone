output "repository_id" { value = google_artifact_registry_repository.this.repository_id }
output "repository_name" { value = google_artifact_registry_repository.this.name }
output "registry_host" {
  description = "docker login / image prefix for this repository."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}"
}
