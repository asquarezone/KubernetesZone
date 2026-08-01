output "cluster_name" { value = aws_eks_cluster.this.name }
output "cluster_arn" { value = aws_eks_cluster.this.arn }
output "cluster_endpoint" { value = aws_eks_cluster.this.endpoint }
output "cluster_version" { value = aws_eks_cluster.this.version }

output "oidc_issuer_url" {
  description = "Needed for IRSA federation - the analogue of the AKS OIDC issuer."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" { value = aws_iam_openid_connect_provider.this.arn }

output "cluster_certificate_authority_data" {
  value     = aws_eks_cluster.this.certificate_authority[0].data
  sensitive = true
}

output "node_role_arn" { value = aws_iam_role.node.arn }
output "node_role_name" { value = aws_iam_role.node.name }

output "autoscaler_role_arn" {
  description = "Annotate the cluster-autoscaler ServiceAccount with this."
  value       = aws_iam_role.autoscaler.arn
}

output "lb_controller_role_arn" {
  description = "Annotate the aws-load-balancer-controller ServiceAccount with this."
  value       = aws_iam_role.lb_controller.arn
}

output "lb_controller_role_name" { value = aws_iam_role.lb_controller.name }

output "cloudwatch_log_group_name" { value = aws_cloudwatch_log_group.cluster.name }

output "node_group_names" {
  value = compact([
    aws_eks_node_group.system.node_group_name,
    aws_eks_node_group.user.node_group_name,
    var.enable_spot_pool ? aws_eks_node_group.spot[0].node_group_name : "",
  ])
}
