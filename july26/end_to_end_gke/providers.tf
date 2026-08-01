# ---------------------------------------------------------------------------
# Provider set: HashiCorp-published registry namespaces only.
#
#   hashicorp/google  - the official HashiCorp Google Cloud provider
#   hashicorp/random  - name uniqueness helper
#
# Note that hashicorp/google-beta is NOT used. Several GKE features in this
# lab (Managed Prometheus, Gateway API, cost allocation) were beta-only for a
# long time and most tutorials still reach for google-beta out of habit. They
# are all GA in the google provider now, so the extra provider buys nothing.
#
# Also deliberately NOT used: the kubernetes and helm providers. Configuring
# them from an output of a cluster that does not exist yet is the classic
# chicken-and-egg apply failure. In-cluster components go in scripts/.
# ---------------------------------------------------------------------------
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # Applied to resources that support it. GCP labels are lowercase-only and
  # reject many characters that Azure tags happily accept.
  default_labels = {
    project     = var.project
    environment = var.env
    owner       = var.owner
    managed_by  = "terraform"
    cost_center = "training"
  }
}

data "google_client_config" "current" {}
data "google_project" "current" {
  project_id = var.project_id
}
