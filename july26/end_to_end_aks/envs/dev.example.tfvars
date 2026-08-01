# ---------------------------------------------------------------------------
# Lab defaults. Copy to your own file and set subscription_id.
# ---------------------------------------------------------------------------
subscription_id = "00000000-0000-0000-0000-000000000000"
location        = "eastus"
project         = "aksstore"
env             = "dev"
owner           = "student-name"

# Cluster sizing
system_node_vm_size   = "Standard_D2s_v5"
system_node_min_count = 1
system_node_max_count = 3

user_node_vm_size   = "Standard_D2s_v5"
user_node_min_count = 1
user_node_max_count = 5
max_pods_per_node   = 50

# Set true once students understand node taints
system_pool_critical_addons_only = false
enable_spot_pool                 = false

# Features
enable_acr         = true
enable_grafana     = true
alert_email        = ""
log_retention_days = 30
