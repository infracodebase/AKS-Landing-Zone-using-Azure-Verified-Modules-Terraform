output "cluster_id" {
  description = "The Kubernetes Managed Cluster ID"
  value       = module.aks.resource_id
}

output "cluster_name" {
  description = "The name of the AKS cluster"
  value       = module.aks.fqdn
}

output "cluster_fqdn" {
  description = "The FQDN of the AKS cluster"
  value       = module.aks.fqdn
}

output "cluster_private_fqdn" {
  description = "The private FQDN of the AKS cluster"
  value       = module.aks.private_fqdn
}

output "cluster_identity" {
  description = "The identity of the AKS cluster"
  value = {
    principal_id = module.aks.identity_principal_id
    tenant_id    = module.aks.identity_tenant_id
  }
}

output "kubelet_identity" {
  description = "The kubelet identity configuration"
  value = {
    client_id                 = module.aks.kubelet_identity_client_id
    object_id                 = module.aks.kubelet_identity_object_id
    user_assigned_identity_id = module.aks.kubelet_identity_user_assigned_identity_id
  }
}

output "kube_config_raw" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = module.aks.kube_config_raw
  sensitive   = true
}

output "kube_admin_config_raw" {
  description = "Raw admin kubeconfig for the AKS cluster"
  value       = module.aks.kube_admin_config_raw
  sensitive   = true
}

output "current_kubernetes_version" {
  description = "The current version running on the AKS cluster"
  value       = module.aks.current_kubernetes_version
}

output "oidc_issuer_url" {
  description = "The OIDC issuer URL that is associated with the cluster"
  value       = module.aks.oidc_issuer_url
}

output "node_resource_group" {
  description = "The auto-generated Resource Group containing resources for the Managed Kubernetes Cluster"
  value       = module.aks.node_resource_group
}

output "resource_group_name" {
  description = "The name of the resource group containing the AKS cluster"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "The location of the resource group containing the AKS cluster"
  value       = azurerm_resource_group.main.location
}

output "vnet_id" {
  description = "The ID of the virtual network"
  value       = module.vnet.resource_id
}

output "aks_subnet_id" {
  description = "The ID of the AKS subnet"
  value       = module.vnet.subnets["aks"].resource_id
}

output "private_link_subnet_id" {
  description = "The ID of the private link subnet"
  value       = module.vnet.subnets["private_link"].resource_id
}

output "container_registry_id" {
  description = "The ID of the Azure Container Registry"
  value       = var.enable_container_registry ? azurerm_container_registry.main[0].id : null
}

output "container_registry_login_server" {
  description = "The login server URL of the Azure Container Registry"
  value       = var.enable_container_registry ? azurerm_container_registry.main[0].login_server : null
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace"
  value       = var.enable_oms_agent ? azurerm_log_analytics_workspace.main[0].id : null
}

output "key_vault_id" {
  description = "The ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "user_assigned_identity_id" {
  description = "The ID of the user assigned managed identity"
  value       = azurerm_user_assigned_identity.aks.id
}

output "user_assigned_identity_client_id" {
  description = "The client ID of the user assigned managed identity"
  value       = azurerm_user_assigned_identity.aks.client_id
}