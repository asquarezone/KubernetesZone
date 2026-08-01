locals {
  suffix = "${var.project}-${var.env}"

  # GCP labels: lowercase letters, numbers, dashes and underscores only, and
  # the VALUE may not be empty. This is stricter than Azure tags - a value
  # like "Student Name" is rejected outright.
  labels = {
    project     = var.project
    environment = var.env
    owner       = lower(replace(var.owner, "/[^a-zA-Z0-9-_]/", "-"))
    managed_by  = "terraform"
    cost_center = "training"
  }
}
