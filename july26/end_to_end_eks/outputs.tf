output "region" { value = var.region }

output "cluster_name" { value = module.eks.cluster_name }

output "cluster_endpoint" { value = module.eks.cluster_endpoint }

output "vpc_id" { value = module.network.vpc_id }

output "private_subnet_ids" {
  description = "Where the nodes live. The autoscaler grows the ASGs backed by these."
  value       = module.network.private_subnet_ids
}

output "ecr_repository_url" {
  value = var.enable_ecr ? module.ecr[0].repository_url : "ecr-disabled"
}

output "oidc_issuer_url" {
  description = "Needed for IRSA federation (the analogue of the AKS OIDC issuer)."
  value       = module.eks.oidc_issuer_url
}

output "autoscaler_role_arn" {
  description = "Passed to scripts/install-autoscaler.sh to annotate the ServiceAccount."
  value       = module.eks.autoscaler_role_arn
}

output "lb_controller_role_arn" {
  description = "Passed to scripts/install-lb-controller.sh."
  value       = module.eks.lb_controller_role_arn
}

output "amp_query_endpoint" {
  value = module.observability.amp_query_endpoint
}

output "grafana_endpoint" {
  value = module.observability.grafana_endpoint
}

output "sns_topic_arn" { value = module.observability.sns_topic_arn }

output "get_credentials_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "watch_autoscaler_command" {
  description = "On EKS the autoscaler is a Deployment you own - so you read its logs, not the cloud's."
  value       = "kubectl -n kube-system logs -f deploy/cluster-autoscaler"
}
