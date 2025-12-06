locals {
  # Common naming convention
  name_prefix = "${var.cluster_name}-${var.environment}"

  # Network configuration
  vnet_address_space  = ["10.0.0.0/16"]
  aks_subnet_cidr     = ["10.0.1.0/24"]
  private_link_subnet = ["10.0.2.0/24"]
  app_gateway_subnet  = ["10.0.3.0/24"]
  pod_cidr            = "192.168.0.0/16"
  service_cidr        = "10.1.0.0/16"
  dns_service_ip      = "10.1.0.10"

  # Resource naming with CAF compliance
  resource_group_name = var.resource_group_name
  cluster_name        = var.cluster_name
  vnet_name           = "vnet-${local.name_prefix}"
  acr_name            = replace("acr${var.cluster_name}${var.environment}", "-", "")
  log_analytics_name  = "law-${local.name_prefix}"
  key_vault_name      = "kv-${local.name_prefix}-${random_string.suffix.result}"

  # Common tags following Azure tagging strategy
  common_tags = merge(var.tags, {
    Environment   = var.environment
    ManagedBy     = "Terraform"
    Project       = var.cluster_name
    SecurityLevel = "Private"
    CostCenter    = var.environment
    LastUpdated   = timestamp()
  })
}