resource "random_string" "ecr" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# ---------------------------------------------------------------------------
# ECR repository.
#
# Unlike ACR, an ECR repository name is only unique within the account and
# region, not globally - so the random suffix is cosmetic parity with the AKS
# lab rather than a hard requirement. It still helps when several students
# share one account.
#
# There is no "admin user" to disable: ECR has no static credentials at all.
# Access is always IAM, and the kubelet authenticates with the node role
# (AmazonEC2ContainerRegistryReadOnly, attached in modules/eks).
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "this" {
  name                 = "${var.suffix}-${random_string.ecr.result}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # lab convenience: destroy works even with images

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

# Keep the repo from growing without bound - the analogue of the AKS image
# cleaner, though this one prunes the registry rather than the nodes.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 10 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
