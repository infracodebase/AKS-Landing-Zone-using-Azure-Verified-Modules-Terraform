# Private AKS Cluster Configuration
# Production-ready configuration following Azure security best practices

# Basic Configuration
environment         = "prod"
location            = "East US 2"
resource_group_name = "rg-mycompany-aks-prod"
cluster_name        = "aks-mycompany-prod"

# Kubernetes Configuration
kubernetes_version = "1.30"

# Network Configuration
enable_private_cluster  = true
enable_private_dns_zone = true
network_policy          = "cilium"

# Node Pool Configuration
default_node_pool_vm_size   = "Standard_D4d_v5"
default_node_pool_min_count = 3
default_node_pool_max_count = 20
enable_auto_scaling         = true

# Security & RBAC
enable_azure_rbac = true
admin_group_object_ids = [
  "12345678-1234-1234-1234-123456789012" # Replace with your Azure AD group object ID
]

# Container Registry
enable_container_registry = true
acr_sku                   = "Premium"

# Monitoring & Security
enable_defender  = true
enable_oms_agent = true

# Tags
tags = {
  Owner              = "Platform Team"
  Environment        = "Production"
  CostCenter         = "IT-Infrastructure"
  Project            = "MyCompany-AKS"
  Criticality        = "High"
  DataClassification = "Internal"
}