variable "project_id" {
  description = "GCP project ID (not the display name, and not the number)."
  type        = string
}

variable "region" {
  description = "GCP region. The cluster is regional, so nodes spread across its zones."
  type        = string
  default     = "us-central1"
}

variable "project" {
  description = "Short project name used in resource names."
  type        = string
  default     = "gkestore"
}

variable "env" {
  description = "Environment name (dev / test / prod)."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Label value - who owns this lab environment."
  type        = string
  default     = "learning-thoughts-lab"
}

# ---------------------------------------------------------------------------
# Cluster shape
# ---------------------------------------------------------------------------
variable "regional_cluster" {
  description = <<-EOT
    true  = regional control plane, nodes in 3 zones (HA, and the node COUNTS
            below are PER ZONE - so min_count 1 means 3 nodes, not 1)
    false = zonal control plane, nodes in one zone (cheaper, no control-plane
            SLA, and counts are literal)

    This per-zone multiplication is the single most common surprise in GKE
    sizing. Read variables system_node_min_count and user_node_min_count with
    that in mind.
  EOT
  type        = bool
  default     = false
}

variable "zone" {
  description = "Zone for a zonal cluster. Ignored when regional_cluster = true."
  type        = string
  default     = "us-central1-a"
}

variable "kubernetes_version" {
  description = "Release channel handles upgrades; this pins the initial minor version prefix."
  type        = string
  default     = null
}

variable "release_channel" {
  description = "RAPID / REGULAR / STABLE / UNSPECIFIED. REGULAR is the sane default."
  type        = string
  default     = "REGULAR"
}

variable "system_node_machine_type" {
  description = "e2-standard-2 is 2 vCPU / 8 GiB - the GKE analogue of D2s_v4 / t3.large."
  type        = string
  default     = "e2-standard-2"
}

variable "system_node_min_count" {
  description = "PER ZONE floor. Multiply by 3 for a regional cluster."
  type        = number
  default     = 1
}

variable "system_node_max_count" {
  description = "PER ZONE ceiling. Multiply by 3 for a regional cluster."
  type        = number
  default     = 2
}

variable "user_node_machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "user_node_min_count" {
  description = "PER ZONE floor for the cluster autoscaler on the application pool."
  type        = number
  default     = 1
}

variable "user_node_max_count" {
  description = "PER ZONE ceiling for the cluster autoscaler on the application pool."
  type        = number
  default     = 3
}

variable "max_pods_per_node" {
  type    = number
  default = 50
}

variable "system_pool_critical_addons_only" {
  description = <<-EOT
    When true the system pool is tainted CriticalAddonsOnly=true:NoSchedule so
    only add-ons land there and all workload pods are forced onto the user
    pool. Production-correct, but students must remember the taint.
  EOT
  type        = bool
  default     = false
}

variable "enable_spot_pool" {
  description = "Add a Spot node pool to demonstrate cost-optimised burst capacity."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "subnet_cidr" {
  description = "Primary range - node IPs come from here."
  type        = string
  default     = "10.10.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary range for pods. VPC-native aliasing, NOT an overlay."
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range for Services. Must not overlap the others."
  type        = string
  default     = "10.30.0.0/20"
}

variable "master_ipv4_cidr" {
  description = "/28 for the private control plane. Must not overlap anything else."
  type        = string
  default     = "172.16.0.0/28"
}

variable "private_nodes" {
  description = "Nodes get no public IPs; egress goes via Cloud NAT. Production-correct."
  type        = bool
  default     = true
}

variable "authorized_networks" {
  description = "CIDRs allowed to reach the control plane endpoint."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [{
    cidr_block   = "0.0.0.0/0"
    display_name = "everywhere-LAB-ONLY"
  }]
}

# ---------------------------------------------------------------------------
# Features
# ---------------------------------------------------------------------------
variable "enable_artifact_registry" {
  type    = bool
  default = true
}

variable "enable_managed_prometheus" {
  description = "Google Cloud Managed Service for Prometheus. Effectively free to enable."
  type        = bool
  default     = true
}

variable "enable_grafana" {
  description = <<-EOT
    GCP has NO managed Grafana service. When true, scripts/install-grafana.sh
    deploys Grafana into the cluster with the Google Cloud Monitoring
    datasource. This is the one place the three labs genuinely diverge - see
    README Part 10.
  EOT
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email for the Cloud Monitoring notification channel. Empty = none."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "deletion_protection" {
  description = "GKE defaults this to TRUE and it will block terraform destroy."
  type        = bool
  default     = false
}
