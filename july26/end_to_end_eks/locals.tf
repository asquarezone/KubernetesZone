locals {
  suffix = "${var.project}-${var.env}"

  # default_tags on the provider already stamps project/environment/owner/etc.
  # This map is for the places that need tags passed explicitly - notably the
  # cluster-autoscaler auto-discovery tags on the node group ASGs.
  tags = {
    project     = var.project
    environment = var.env
    owner       = var.owner
    managed_by  = "terraform"
    cost_center = "training"
  }

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Address plan - see modules/network/main.tf for the full explanation.
  public_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 1)]
}
