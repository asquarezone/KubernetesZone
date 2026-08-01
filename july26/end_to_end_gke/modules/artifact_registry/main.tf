resource "random_string" "ar" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# ---------------------------------------------------------------------------
# Artifact Registry - the successor to Container Registry (gcr.io).
#
# Unlike ACR, the repository name is only unique within the project and
# location, so the random suffix is cosmetic parity with the AKS lab.
#
# There is no admin user to disable: access is always IAM. The node service
# account gets roles/artifactregistry.reader in modules/gke, which is the
# direct analogue of the AcrPull role assignment on AKS and of the
# AmazonEC2ContainerRegistryReadOnly policy on EKS.
# ---------------------------------------------------------------------------
resource "google_artifact_registry_repository" "this" {
  project       = var.project_id
  location      = var.region
  repository_id = "ar-${var.suffix}-${random_string.ar.result}"
  description   = "Container images for the GKE Store lab"
  format        = "DOCKER"
  labels        = var.labels

  docker_config {
    immutable_tags = false # lab convenience; true is better practice
  }

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      older_than = "2592000s" # 30 days
    }
  }
}
