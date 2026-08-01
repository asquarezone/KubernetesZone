output "resource_group_name" { value = azurerm_resource_group.this.name }
output "resource_group_id"   { value = azurerm_resource_group.this.id }
output "location"            { value = azurerm_resource_group.this.location }
output "vnet_id"             { value = azurerm_virtual_network.this.id }
output "vnet_name"           { value = azurerm_virtual_network.this.name }
output "system_subnet_id"    { value = azurerm_subnet.aks_system.id }
output "user_subnet_id"      { value = azurerm_subnet.aks_user.id }
output "appgw_subnet_id"     { value = azurerm_subnet.appgw.id }
