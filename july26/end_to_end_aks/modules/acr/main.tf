resource "random_string" "acr" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_container_registry" "this" {
  # ACR names are globally unique, alphanumeric only, no hyphens.
  name                          = lower(replace("acr${var.suffix}${random_string.acr.result}", "-", ""))
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.sku
  admin_enabled                 = false # use RBAC + managed identity, never admin creds
  public_network_access_enabled = true
  tags                          = var.tags
}
