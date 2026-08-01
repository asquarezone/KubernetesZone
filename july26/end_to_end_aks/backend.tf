terraform {
  required_version = ">= 1.9.0"

  # -------------------------------------------------------------------------
  # Remote state. Run ./scripts/bootstrap-backend.sh FIRST, then paste the
  # printed storage account name below (it is globally unique per student).
  #
  # AUTHENTICATION - pick ONE:
  #
  #   A) Entra ID (default below, use_azuread_auth = true)
  #      Requires the DATA-PLANE role "Storage Blob Data Contributor" on the
  #      storage account. Subscription Contributor is NOT enough - that is a
  #      control-plane role and cannot list blobs. Grant it with:
  #
  #        ./scripts/grant-backend-access.sh <storage-account-name>
  #
  #   B) Shared key - use when you cannot create role assignments:
  #        export ARM_ACCESS_KEY=$(az storage account keys list \
  #          -g rg-tfstate-aksstore -n <SA> --query '[0].value' -o tsv)
  #      ...and set use_azuread_auth = false below.
  #
  # For a purely local lab run you may comment this whole block out.
  # -------------------------------------------------------------------------
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-aksstore"
    storage_account_name = "REPLACE_ME_WITH_YOUR_SA"
    container_name       = "tfstate"
    key                  = "aks-store/dev.terraform.tfstate"
    use_azuread_auth     = true
  }
}
