# Ressourcengruppe
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

# VNet: 10.100.0.0/16 
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet1-${var.prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.100.0.0/16"]
  dns_servers         = ["10.100.3.10", "168.63.129.16"] 
  tags                = var.tags
}

# Subnet 1: Jump Host (10.100.1.0/24)
resource "azurerm_subnet" "jump" {
  name                 = "subnet1-vnet1-${var.prefix}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.100.1.0/24"]
  
  depends_on = [azurerm_virtual_network.vnet]
}

# Subnet 2: SGW (10.100.2.0/24)
resource "azurerm_subnet" "sgw" {
  name                 = "subnet2-vnet1-${var.prefix}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.100.2.0/24"]
  
  depends_on = [azurerm_virtual_network.vnet]
}

# Subnet 3: AD VMs (10.100.3.0/24)
resource "azurerm_subnet" "ad" {
  name                 = "subnet3-vnet1-${var.prefix}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.100.3.0/24"]
  
  depends_on = [azurerm_virtual_network.vnet]
}