# User assigned managed identity for AKS
resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-${local.name_prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# Role assignment for AKS to access ACR
resource "azurerm_role_assignment" "aks_acr" {
  count                = var.enable_container_registry ? 1 : 0
  scope                = azurerm_container_registry.main[0].id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# Azure Container Registry (Private)
resource "azurerm_container_registry" "main" {
  count                         = var.enable_container_registry ? 1 : 0
  name                          = local.acr_name
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  sku                           = var.acr_sku
  admin_enabled                 = false
  public_network_access_enabled = false

  # Security configurations
  network_rule_bypass_option = "AzureServices"

  # Enable vulnerability scanning for Premium SKU
  dynamic "quarantine_policy" {
    for_each = var.acr_sku == "Premium" ? [1] : []
    content {
      enabled = true
    }
  }

  dynamic "trust_policy" {
    for_each = var.acr_sku == "Premium" ? [1] : []
    content {
      enabled = true
    }
  }

  dynamic "retention_policy" {
    for_each = var.acr_sku == "Premium" ? [1] : []
    content {
      enabled = true
      days    = 7
    }
  }

  tags = local.common_tags
}

# Private endpoint for ACR
resource "azurerm_private_endpoint" "acr" {
  count               = var.enable_container_registry ? 1 : 0
  name                = "pe-${local.acr_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.vnet.subnets["private_link"].resource_id

  private_service_connection {
    name                           = "psc-${local.acr_name}"
    private_connection_resource_id = azurerm_container_registry.main[0].id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdz-group-${local.acr_name}"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr[0].id]
  }

  tags = local.common_tags
}

# AKS Cluster using Azure Verified Module
module "aks" {
  source  = "Azure/avm-ptn-aks-production/azurerm"
  version = "~> 0.5.0"

  name                = local.cluster_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kubernetes_version  = var.kubernetes_version

  # Private cluster configuration
  private_dns_zone_id_enabled = var.enable_private_dns_zone
  private_dns_zone_id         = var.enable_private_dns_zone ? azurerm_private_dns_zone.aks[0].id : null

  # Network configuration for private cluster
  network = {
    node_subnet_id = module.vnet.subnets["aks"].resource_id
    pod_cidr       = local.pod_cidr
    service_cidr   = local.service_cidr
    dns_service_ip = local.dns_service_ip
  }

  # Network policy for security
  network_policy = var.network_policy

  # Default node pool configuration
  default_node_pool_vm_sku = var.default_node_pool_vm_size
  os_disk_type             = "Managed"
  os_sku                   = "AzureLinux"

  # Managed identity configuration
  managed_identities = {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.aks.id]
  }

  # RBAC configuration
  rbac_aad_azure_rbac_enabled     = var.enable_azure_rbac
  rbac_aad_tenant_id              = data.azurerm_client_config.current.tenant_id
  rbac_aad_admin_group_object_ids = var.admin_group_object_ids

  # Container registry configuration
  acr = var.enable_container_registry ? {
    name                          = azurerm_container_registry.main[0].name
    subnet_resource_id            = module.vnet.subnets["private_link"].resource_id
    private_dns_zone_resource_ids = [azurerm_private_dns_zone.acr[0].id]
    zone_redundancy_enabled       = var.acr_sku == "Premium"
  } : null

  # Additional node pools for workload separation
  node_pools = {
    system = {
      name                 = "system"
      vm_size              = "Standard_D4d_v5"
      orchestrator_version = var.kubernetes_version
      min_count            = 2
      max_count            = 5
      mode                 = "System"
      os_sku               = "AzureLinux"
      os_disk_type         = "Managed"
      labels = {
        "nodepool-type" = "system"
        "environment"   = var.environment
      }
    }

    user = {
      name                 = "user"
      vm_size              = var.default_node_pool_vm_size
      orchestrator_version = var.kubernetes_version
      min_count            = var.default_node_pool_min_count
      max_count            = var.default_node_pool_max_count
      mode                 = "User"
      os_sku               = "AzureLinux"
      os_disk_type         = "Managed"
      labels = {
        "nodepool-type" = "user"
        "environment"   = var.environment
      }
    }
  }

  # Monitoring configuration
  monitor_metrics = var.enable_oms_agent ? {
    annotations_allowed = "deployment,daemonset,replicaset"
    labels_allowed      = "app,component,environment"
  } : null

  # Security and compliance tags
  tags = local.common_tags

  depends_on = [
    azurerm_role_assignment.aks_acr,
    azurerm_private_dns_zone_virtual_network_link.aks,
    azurerm_private_dns_zone_virtual_network_link.acr
  ]
}