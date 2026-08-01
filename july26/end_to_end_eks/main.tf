# ===========================================================================
#  EKS Store - End to End Infrastructure
#  Learning Thoughts | "Pets, Pods & Pipelines" (AWS edition)
#
#  Order of construction (Terraform works this out from the references):
#    network -> ecr -> eks -> observability -> monitoring
#
#  Note the ordering difference from the AKS lab: there, observability was
#  built BEFORE the cluster because the cluster referenced the Log Analytics
#  workspace id. Here the managed Prometheus SCRAPER references the cluster,
#  so observability comes after. Same graph, opposite arrow.
# ===========================================================================

module "network" {
  source = "./modules/network"

  suffix               = local.suffix
  tags                 = local.tags
  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = local.public_subnet_cidrs
  private_subnet_cidrs = local.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
}

module "ecr" {
  count  = var.enable_ecr ? 1 : 0
  source = "./modules/ecr"

  suffix = local.suffix
  tags   = local.tags
}

module "eks" {
  source = "./modules/eks"

  suffix             = local.suffix
  tags               = local.tags
  kubernetes_version = var.kubernetes_version
  log_retention_days = var.log_retention_days

  private_subnet_ids     = module.network.private_subnet_ids
  public_subnet_ids      = module.network.public_subnet_ids
  node_security_group_id = module.network.node_security_group_id

  system_node_instance_type        = var.system_node_instance_type
  system_node_min_count            = var.system_node_min_count
  system_node_max_count            = var.system_node_max_count
  user_node_instance_type          = var.user_node_instance_type
  user_node_min_count              = var.user_node_min_count
  user_node_max_count              = var.user_node_max_count
  system_pool_critical_addons_only = var.system_pool_critical_addons_only
  enable_spot_pool                 = var.enable_spot_pool
  enable_container_insights        = true
}

module "observability" {
  source = "./modules/observability"

  suffix             = local.suffix
  tags               = local.tags
  log_retention_days = var.log_retention_days
  alert_email        = var.alert_email

  enable_grafana            = var.enable_grafana
  enable_managed_prometheus = var.enable_managed_prometheus

  eks_cluster_arn    = module.eks.cluster_arn
  eks_cluster_name   = module.eks.cluster_name
  private_subnet_ids = module.network.private_subnet_ids
}

module "monitoring" {
  source = "./modules/monitoring"

  suffix             = local.suffix
  tags               = local.tags
  eks_cluster_name   = module.eks.cluster_name
  sns_topic_arn      = module.observability.sns_topic_arn
  app_log_group_name = module.observability.app_log_group_name
}

# ---------------------------------------------------------------------------
# Access entry for the Terraform caller.
#
# This is the EKS analogue of the "Azure Kubernetes Service RBAC Cluster
# Admin" role assignment in the AKS lab. With authentication_mode = "API",
# access is granted through access entries rather than the old aws-auth
# ConfigMap.
#
# bootstrap_cluster_creator_admin_permissions = true (in modules/eks) already
# grants the CREATING principal admin. This block is here so you can grant a
# SECOND principal - e.g. the instructor, or the role students assume when
# the cluster was built by a pipeline. Leave additional_admin_principal_arn
# empty to skip it.
# ---------------------------------------------------------------------------
resource "aws_eks_access_entry" "additional_admin" {
  count = var.additional_admin_principal_arn == "" ? 0 : 1

  cluster_name  = module.eks.cluster_name
  principal_arn = var.additional_admin_principal_arn
  type          = "STANDARD"
  tags          = local.tags
}

resource "aws_eks_access_policy_association" "additional_admin" {
  count = var.additional_admin_principal_arn == "" ? 0 : 1

  cluster_name  = module.eks.cluster_name
  principal_arn = var.additional_admin_principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.additional_admin]
}
