# Backend configuration for Terraform state
# This should be customized based on your organization's requirements

terraform {
  # For development/testing purposes, comment out the backend to use local state
  # backend "azurerm" {
  #   # Backend configuration - these values should be customized for your environment
  #   # You can also configure these via:
  #   # 1. Environment variables (ARM_*)
  #   # 2. Command line (-backend-config)
  #   # 3. Terraform Cloud/Enterprise backend configuration

  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "tfstateaks001"  # Must be globally unique - customize this
  #   container_name      = "tfstate"
  #   key                 = "aks/terraform.tfstate"

  #   # Security best practices - uncomment when using with Azure credentials
  #   # use_msi              = true  # Use Managed Service Identity
  #   # use_azuread_auth     = true  # Use Azure AD authentication
  #   # snapshot             = true  # Enable state snapshots
  # }
}

# Alternative: Remote backend examples for different scenarios

# Example 1: Terraform Cloud
# terraform {
#   cloud {
#     organization = "your-org-name"
#     workspaces {
#       name = "aks-infrastructure"
#       # Or use tags for multiple workspaces
#       # tags = ["aks", "infrastructure"]
#     }
#   }
# }

# Example 2: S3 backend (if using multi-cloud)
# terraform {
#   backend "s3" {
#     bucket = "your-terraform-state-bucket"
#     key    = "aks/terraform.tfstate"
#     region = "us-east-1"
#
#     # Security configurations
#     encrypt        = true
#     dynamodb_table = "terraform-state-lock"
#   }
# }