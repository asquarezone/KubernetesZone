# ===========================================================================
#  EKS cluster, node groups, OIDC provider and the IAM roles that make
#  IRSA work.
#
#  THE HEADLINE DIFFERENCE FROM AKS
#  --------------------------------
#  On AKS the cluster autoscaler is a control-plane feature: you set
#  auto_scaler_profile and Azure runs it for you. On EKS it is NOT. The
#  cluster autoscaler is an ordinary Deployment that YOU install into
#  kube-system, and it needs:
#
#    1. IAM permission to describe and resize the node group ASGs  (below)
#    2. Auto-discovery tags on those ASGs                          (below)
#    3. The Deployment itself         (scripts/install-autoscaler.sh)
#
#  Terraform builds 1 and 2. Step 3 is a script because installing it from
#  Terraform would require the kubernetes/helm providers, and configuring
#  those from a not-yet-created cluster is the classic chicken-and-egg apply
#  failure. See providers.tf.
# ===========================================================================

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Control plane IAM role
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "role-eks-cluster-${var.suffix}"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
  ])
  role       = aws_iam_role.cluster.name
  policy_arn = each.value
}

# ---------------------------------------------------------------------------
# CloudWatch log group for control-plane logs.
#
# Create it explicitly so retention and deletion are OURS. If you let EKS
# create it implicitly it survives terraform destroy and silently accrues
# charges - a classic "I destroyed everything, why am I still billed" moment.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/eks-${var.suffix}/cluster"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# The cluster
# ---------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = "eks-${var.suffix}"
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version
  tags     = var.tags

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    security_group_ids      = [var.node_security_group_id]
    endpoint_private_access = true
    endpoint_public_access  = true

    # Lock this down to your office/VPN CIDR for anything real. "Open to the
    # internet, but authenticated" is fine for a lab and terrible for prod.
    public_access_cidrs = var.public_access_cidrs
  }

  # API = IAM principals are mapped via EKS access entries, not the legacy
  # aws-auth ConfigMap. This is the modern path and it is far harder to lock
  # yourself out of.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  kubernetes_network_config {
    service_ipv4_cidr = var.service_ipv4_cidr
    ip_family         = "ipv4"
  }

  # The EKS equivalent of Azure's diagnostic settings. Note what is NOT in
  # this list: there is no "cluster-autoscaler" category, because on EKS the
  # autoscaler is not part of the control plane. You read its logs with
  # kubectl, not CloudWatch. See README Part 8.
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

# ---------------------------------------------------------------------------
# OIDC provider - the foundation of IRSA (IAM Roles for Service Accounts).
#
# This is the exact analogue of the AKS oidc_issuer_url + workload identity.
# It lets a Kubernetes ServiceAccount assume an IAM role with no static keys.
# ---------------------------------------------------------------------------
# NOTE ON THE THUMBPRINT: most tutorials compute this with the hashicorp/tls
# provider (data.tls_certificate). That would be a third provider in the
# dependency graph for one string. AWS publishes the EKS OIDC root CA
# thumbprint as a well-known constant, and IAM no longer validates it for
# EKS-hosted issuers, so we pass the documented value and keep the provider
# set to aws + random only. See Appendix C.
resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
  tags            = var.tags
}

locals {
  oidc_issuer_bare = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

# ---------------------------------------------------------------------------
# Node group IAM role
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "role-eks-node-${var.suffix}"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    # Lets the kubelet pull from ECR with no imagePullSecret - the analogue of
    # the AcrPull role assignment on AKS.
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    # Container Insights / CloudWatch agent needs this on the node role.
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy",
    # SSM makes "why did this node not join" debuggable without SSH.
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# ---------------------------------------------------------------------------
# SYSTEM node group - CoreDNS, metrics-server, the monitoring agents and
# (critically) the cluster autoscaler Deployment itself.
# ---------------------------------------------------------------------------
resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = [var.system_node_instance_type]
  capacity_type   = "ON_DEMAND"
  disk_size       = 50

  scaling_config {
    min_size     = var.system_node_min_count
    max_size     = var.system_node_max_count
    desired_size = var.system_node_min_count
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = {
    "nodepool-type" = "system"
    "workload"      = "platform"
  }

  dynamic "taint" {
    for_each = var.system_pool_critical_addons_only ? [1] : []
    content {
      key    = "CriticalAddonsOnly"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }

  # THESE TAGS ARE THE AUTOSCALER'S ONLY WAY TO FIND THIS NODE GROUP.
  # Managed node groups propagate tags to the underlying ASG, and the cluster
  # autoscaler is started with --node-group-auto-discovery matching exactly
  # these two keys. Get them wrong and the autoscaler runs happily, finds no
  # node groups, and never scales anything - with no error.
  tags = merge(var.tags, {
    "k8s.io/cluster-autoscaler/enabled"                           = "true"
    "k8s.io/cluster-autoscaler/eks-${var.suffix}"                 = "owned"
    "k8s.io/cluster-autoscaler/node-template/label/nodepool-type" = "system"
  })

  lifecycle {
    # desired_size belongs to the autoscaler, not to Terraform. Leaving it
    # under Terraform's control causes permanent drift and, worse, scales your
    # cluster back down on every apply.
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# ---------------------------------------------------------------------------
# USER node group - where the store microservices actually run. This is the
# pool students watch scale under load.
# ---------------------------------------------------------------------------
resource "aws_eks_node_group" "user" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "user"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = [var.user_node_instance_type]
  capacity_type   = "ON_DEMAND"
  disk_size       = 50

  scaling_config {
    min_size     = var.user_node_min_count
    max_size     = var.user_node_max_count
    desired_size = var.user_node_min_count
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = {
    "nodepool-type" = "user"
    "workload"      = "apps"
  }

  tags = merge(var.tags, {
    "k8s.io/cluster-autoscaler/enabled"                           = "true"
    "k8s.io/cluster-autoscaler/eks-${var.suffix}"                 = "owned"
    "k8s.io/cluster-autoscaler/node-template/label/nodepool-type" = "user"
  })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# ---------------------------------------------------------------------------
# Optional Spot node group - burst capacity at a large discount.
# Tainted so only pods that explicitly tolerate eviction land here.
# ---------------------------------------------------------------------------
resource "aws_eks_node_group" "spot" {
  count = var.enable_spot_pool ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "spot"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  # Give Spot several types to choose from - a single type is far more likely
  # to be interrupted or unavailable.
  instance_types = var.spot_instance_types
  capacity_type  = "SPOT"
  disk_size      = 50

  scaling_config {
    min_size     = 0
    max_size     = 3
    desired_size = 0
  }

  labels = {
    "nodepool-type" = "spot"
  }

  taint {
    key    = "spot"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = merge(var.tags, {
    "k8s.io/cluster-autoscaler/enabled"                           = "true"
    "k8s.io/cluster-autoscaler/eks-${var.suffix}"                 = "owned"
    "k8s.io/cluster-autoscaler/node-template/label/nodepool-type" = "spot"
  })

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

# ---------------------------------------------------------------------------
# IRSA role for the cluster autoscaler.
#
# The trust policy is the interesting part: it says "the ServiceAccount named
# cluster-autoscaler in namespace kube-system, in THIS cluster's OIDC issuer,
# may assume this role." No keys, no secrets, and it stops working the moment
# the cluster is deleted.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "autoscaler_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_bare}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_bare}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "autoscaler" {
  name               = "role-cluster-autoscaler-${var.suffix}"
  assume_role_policy = data.aws_iam_policy_document.autoscaler_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "autoscaler" {
  # Read-only discovery - safe to leave unscoped.
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
  }

  # The mutating actions, scoped by the auto-discovery tag so this role can
  # only resize node groups belonging to THIS cluster.
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/eks-${var.suffix}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_role_policy" "autoscaler" {
  name   = "cluster-autoscaler-${var.suffix}"
  role   = aws_iam_role.autoscaler.id
  policy = data.aws_iam_policy_document.autoscaler.json
}

# ---------------------------------------------------------------------------
# IRSA role for the AWS Load Balancer Controller (the managed-ingress
# analogue of AKS web_app_routing).
#
# The controller's IAM policy is long and AWS revises it; rather than paste a
# stale copy here, scripts/install-lb-controller.sh downloads the current
# official policy document and attaches it to this role.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "lbc_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_bare}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_bare}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "role-lb-controller-${var.suffix}"
  assume_role_policy = data.aws_iam_policy_document.lbc_assume.json
  tags               = var.tags
}

# ---------------------------------------------------------------------------
# EKS managed add-ons.
#
# vpc-cni, coredns and kube-proxy are the baseline. metrics-server is what the
# HPA reads - without it every HPA reports <unknown> forever.
# ---------------------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

# CoreDNS runs as pods, so it needs nodes to exist first.
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags

  depends_on = [aws_eks_node_group.system]
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags

  depends_on = [aws_eks_node_group.system]
}

# Container Insights - the Amazon equivalent of Azure Container Insights.
resource "aws_eks_addon" "cloudwatch_observability" {
  count = var.enable_container_insights ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags

  depends_on = [aws_eks_node_group.system]
}

# ---------------------------------------------------------------------------
# EBS CSI driver - needed by any StatefulSet that asks for a PVC, which
# includes the demo app's database.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_bare}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_bare}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "role-ebs-csi-${var.suffix}"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags

  depends_on = [aws_eks_node_group.system]
}
