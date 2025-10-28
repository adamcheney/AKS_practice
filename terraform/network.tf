# Create the virtual network (VPC in AWS terms)
resource "azurerm_virtual_network" "aks_vnet" {
  name                = "cheneyaw-aks-vnet"
  location = data.azurerm_resource_group.aks_from_mac.location
  resource_group_name = data.azurerm_resource_group.aks_from_mac.name
  address_space       = var.vnet_address_space
}

resource "azurerm_subnet" "node" {
  name                 = "nodes"
  resource_group_name  = data.azurerm_resource_group.aks_from_mac.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = var.node_subnet_cidr
}


