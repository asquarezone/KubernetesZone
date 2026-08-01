locals {
  suffix = "${var.project}-${var.env}"

  tags = {
    project     = var.project
    environment = var.env
    owner       = var.owner
    managed_by  = "terraform"
    cost_center = "training"
  }
}
