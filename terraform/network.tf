# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

# Data source for current Azure client configuration
data "azurerm_client_config" "current" {}

# Resource group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Virtual network for AKS cluster
module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "~> 0.7.1"

  name                = local.vnet_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = local.vnet_address_space

  subnets = {
    aks = {
      name             = "snet-aks"
      address_prefixes = local.aks_subnet_cidr

      # Service endpoints for enhanced security
      service_endpoints = [
        "Microsoft.ContainerRegistry",
        "Microsoft.KeyVault",
        "Microsoft.Storage"
      ]

      # Delegation for Azure CNI
      delegation = [{
        name = "aks-delegation"
        service_delegation = [{
          name    = "Microsoft.ContainerService/managedClusters"
          actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }]
      }]
    }

    private_link = {
      name             = "snet-private-link"
      address_prefixes = local.private_link_subnet

      # Disable network policies for private endpoints
      private_endpoint_network_policies_enabled = false

      service_endpoints = [
        "Microsoft.ContainerRegistry",
        "Microsoft.KeyVault"
      ]
    }

    app_gateway = {
      name             = "snet-app-gateway"
      address_prefixes = local.app_gateway_subnet
    }
  }

  tags = local.common_tags
}

# Network Security Group for AKS subnet
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-${local.name_prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Allow inbound from same subnet
  security_rule {
    name                       = "AllowVnetInBound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Allow outbound internet for updates and container pulls
  security_rule {
    name                       = "AllowInternetOutBound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  # Deny all other inbound traffic
  security_rule {
    name                       = "DenyAllInBound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

# Associate NSG with AKS subnet
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = module.vnet.subnets["aks"].resource_id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# Private DNS zones for AKS and ACR
resource "azurerm_private_dns_zone" "aks" {
  count               = var.enable_private_dns_zone ? 1 : 0
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone" "acr" {
  count               = var.enable_container_registry ? 1 : 0
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Link private DNS zones to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  count                 = var.enable_private_dns_zone ? 1 : 0
  name                  = "aks-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.aks[0].name
  virtual_network_id    = module.vnet.resource_id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count                 = var.enable_container_registry ? 1 : 0
  name                  = "acr-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = module.vnet.resource_id
  registration_enabled  = false
  tags                  = local.common_tags
}