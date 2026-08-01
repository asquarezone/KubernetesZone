# ---------------------------------------------------------------------------
# Address plan (memorise this - it is the exam question)
#
#   VNet                 10.10.0.0/16
#   |- snet-aks-system   10.10.1.0/24    251 usable  -> system node IPs
#   |- snet-aks-user     10.10.2.0/23    507 usable  -> autoscaling headroom
#   |- snet-appgw        10.10.10.0/27   reserved for ingress (Step 7)
#
#   Pod CIDR (overlay)   192.168.0.0/16  MUST NOT overlap the VNet
#   Service CIDR         172.16.0.0/16   MUST NOT overlap VNet or pod CIDR
#
# With Azure CNI Overlay the pods draw from the overlay CIDR, so scaling to
# 5 nodes costs 5 VNet IPs - not 5 x max_pods. This is why the cluster
# autoscaler and classic Azure CNI fight each other for address space.
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.suffix}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "aks_system" {
  name                 = "snet-aks-system"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.system_subnet_cidr]
}

resource "azurerm_subnet" "aks_user" {
  name                 = "snet-aks-user"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.user_subnet_cidr]
}

resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.appgw_subnet_cidr]
}

# ---------------------------------------------------------------------------
# NSG - AKS manages most rules itself, but the load balancer health probe
# path must stay open or your Services never become Ready.
# ---------------------------------------------------------------------------
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks-${var.suffix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "allow_lb_probe" {
  name                        = "AllowAzureLoadBalancerInbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.aks.name
}

resource "azurerm_network_security_rule" "allow_http_https" {
  name                        = "AllowWebInbound"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443"]
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.aks.name
}

resource "azurerm_subnet_network_security_group_association" "system" {
  subnet_id                 = azurerm_subnet.aks_system.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

resource "azurerm_subnet_network_security_group_association" "user" {
  subnet_id                 = azurerm_subnet.aks_user.id
  network_security_group_id = azurerm_network_security_group.aks.id
}
