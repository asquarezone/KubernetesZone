# ---------------------------------------------------------------------------
# Lab defaults. Copy to your own file (envs/dev.tfvars) and edit.
# ---------------------------------------------------------------------------
project_id = "REPLACE-WITH-YOUR-PROJECT-ID"
region     = "us-central1"
zone       = "us-central1-a"
project    = "gkestore"
env        = "dev"
owner      = "student-name"

# ---------------------------------------------------------------------------
# Cluster shape
#
# regional_cluster = false gives a ZONAL cluster: node counts below are
# literal, and there is no control-plane SLA. This is the cheap lab default.
#
# regional_cluster = true gives an HA control plane AND spreads nodes across
# 3 zones - at which point every count below is PER ZONE. min_count 1 becomes
# 3 nodes and max_count 3 becomes 9. Check your CPU quota before flipping it.
# ---------------------------------------------------------------------------
regional_cluster = false
release_channel  = "REGULAR"

system_node_machine_type = "e2-standard-2"
system_node_min_count    = 1
system_node_max_count    = 2

user_node_machine_type = "e2-standard-2"
user_node_min_count    = 1
user_node_max_count    = 3

max_pods_per_node = 50

# Set true once students understand node taints
system_pool_critical_addons_only = false
enable_spot_pool                 = false

# ---------------------------------------------------------------------------
# Networking
#
# The pod range is sized by nodes x max_pods_per_node, rounded UP to a power
# of two per node. max_pods_per_node = 50 reserves a /25 (128) per node.
# ---------------------------------------------------------------------------
subnet_cidr      = "10.10.0.0/20"
pods_cidr        = "10.20.0.0/16"
services_cidr    = "10.30.0.0/20"
master_ipv4_cidr = "172.16.0.0/28"
private_nodes    = true

# Features
enable_artifact_registry  = true
enable_managed_prometheus = true

# GCP has NO managed Grafana. true = self-host it in the cluster via
# scripts/install-grafana.sh. false = use Cloud Monitoring dashboards only.
enable_grafana = true

alert_email        = ""
log_retention_days = 30

# GKE sets this true by default and it BLOCKS terraform destroy.
deletion_protection = false
