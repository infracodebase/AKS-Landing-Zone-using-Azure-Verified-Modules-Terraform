variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, staging, prod)"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  type        = string
  description = "Azure region where resources will be created"
  default     = "East US 2"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group where resources will be created"
}

variable "cluster_name" {
  type        = string
  description = "Name of the AKS cluster"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version to use for the AKS cluster (specify minor version only, e.g., '1.30')"
  default     = "1.30"
}

variable "enable_private_cluster" {
  type        = bool
  description = "Enable private cluster configuration"
  default     = true
}

variable "enable_private_dns_zone" {
  type        = bool
  description = "Enable private DNS zone integration"
  default     = true
}

variable "network_policy" {
  type        = string
  description = "Network policy to use with Azure CNI (calico or cilium)"
  default     = "cilium"

  validation {
    condition     = contains(["calico", "cilium"], var.network_policy)
    error_message = "Network policy must be either 'calico' or 'cilium'."
  }
}

variable "default_node_pool_vm_size" {
  type        = string
  description = "VM size for the default node pool"
  default     = "Standard_D4d_v5"
}

variable "default_node_pool_min_count" {
  type        = number
  description = "Minimum number of nodes in the default node pool"
  default     = 2
}

variable "default_node_pool_max_count" {
  type        = number
  description = "Maximum number of nodes in the default node pool"
  default     = 10
}

variable "enable_auto_scaling" {
  type        = bool
  description = "Enable auto scaling for the default node pool"
  default     = true
}

variable "enable_azure_rbac" {
  type        = bool
  description = "Enable Azure RBAC for Kubernetes authorization"
  default     = true
}

variable "admin_group_object_ids" {
  type        = list(string)
  description = "List of Azure AD group object IDs that will have admin access to the cluster"
  default     = []
}

variable "enable_container_registry" {
  type        = bool
  description = "Enable Azure Container Registry creation"
  default     = true
}

variable "acr_sku" {
  type        = string
  description = "SKU for Azure Container Registry"
  default     = "Premium"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "ACR SKU must be one of: Basic, Standard, Premium."
  }
}

variable "enable_defender" {
  type        = bool
  description = "Enable Microsoft Defender for Containers"
  default     = true
}

variable "enable_oms_agent" {
  type        = bool
  description = "Enable OMS agent for Azure Monitor"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}