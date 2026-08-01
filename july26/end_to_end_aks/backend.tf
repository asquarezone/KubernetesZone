terraform {
  required_version = ">= 1.9.0"

  # -------------------------------------------------------------------------
  # Remote state. Run ./scripts/bootstrap-backend.sh FIRST, then fill in the
  # storage_account_name below (it is globally unique per student).
  #
  # For a purely local lab run you may comment this whole block out.
  # -------------------------------------------------------------------------
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-aksstore"
    storage_account_name = "sttfstate298663682"
    container_name       = "tfstate"
    key                  = "aks-store/dev.terraform.tfstate"
    use_azuread_auth     = true
  }
}
