# ---------------------------------------------------------------------------
# Lab defaults. Copy to your own file (envs/dev.tfvars) and edit.
# ---------------------------------------------------------------------------
region  = "us-east-1"
project = "ekstore"
env     = "dev"
owner   = "student-name"

kubernetes_version = "1.31"

# Cluster sizing
#
# Sized for a modest EC2 quota. Check yours FIRST with ./scripts/preflight.sh
# - a new AWS account often has an On-Demand Standard limit of only 5 vCPUs,
# which is not enough to start this lab at all.
#
# Ceiling here is (2 system + 3 user) x 2 vCPU = 10 vCPU.
system_node_instance_type = "t3.large"
system_node_min_count     = 1
system_node_max_count     = 2

user_node_instance_type = "t3.large"
user_node_min_count     = 1
user_node_max_count     = 3

# Set true once students understand node taints
system_pool_critical_addons_only = false
enable_spot_pool                 = false

# Networking
vpc_cidr = "10.10.0.0/16"
az_count = 3

# true  = one NAT gateway (cheap, single point of failure)
# false = one per AZ (production-correct, roughly 3x the NAT cost)
single_nat_gateway = true

# Features
enable_ecr                = true
enable_managed_prometheus = true

# Amazon Managed Grafana REQUIRES AWS IAM Identity Center to be enabled in
# this account first. ./scripts/preflight.sh tells you whether it is.
# Leave false unless you have it.
enable_grafana = false

alert_email        = ""
log_retention_days = 30

# Optional second admin principal (IAM user/role ARN) for kubectl access.
additional_admin_principal_arn = ""
