# ---------------------------------------------------------------------------
# Provider set: HashiCorp-published registry namespaces only.
#
#   hashicorp/azurerm  - the official HashiCorp Azure provider
#   hashicorp/random   - name uniqueness helper
#
# Deliberately NOT used: Azure/azapi, Azure/azuread, Azure/modtm and any other
# provider published under a non-HashiCorp namespace. Every resource in this
# project is expressible in azurerm 4.x, so the extra dependency buys nothing
# and complicates registry allow-listing in locked-down corporate networks.
# ---------------------------------------------------------------------------
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.20"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
}

data "azurerm_client_config" "current" {}
