# ---------------------------------------------------------------------------
# Provider set: HashiCorp-published registry namespaces only.
#
#   hashicorp/aws     - the official HashiCorp AWS provider
#   hashicorp/random  - name uniqueness helper
#
# Deliberately NOT used: any provider published under a non-HashiCorp
# namespace, and deliberately NOT the kubernetes / helm providers either.
#
# Why no kubernetes or helm provider? Because mixing "build the cluster" and
# "deploy into the cluster" into a single apply creates a chicken-and-egg
# dependency: the providers are configured from an output of a resource that
# does not exist yet on the first run. The classic symptom is an apply that
# works for you and fails for every student. In-cluster components are
# installed by scripts/ instead, after the cluster exists.
# ---------------------------------------------------------------------------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project     = var.project
      environment = var.env
      owner       = var.owner
      managed_by  = "terraform"
      cost_center = "training"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
