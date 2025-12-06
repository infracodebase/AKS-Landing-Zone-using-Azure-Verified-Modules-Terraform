# Backend configuration for Terraform state
# This should be customized based on your organization's requirements

terraform {
  backend "azurerm" {
    # Replace these values with your actual backend configuration
    # resource_group_name  = "rg-terraform-state"
    # storage_account_name = "terraformstatexxxxx"  # Must be globally unique
    # container_name      = "tfstate"
    # key                 = "aks/terraform.tfstate"

    # Optional: Use workspace-specific state files
    # key = "aks/${terraform.workspace}/terraform.tfstate"

    # Security best practices
    # use_msi              = true  # Use Managed Service Identity
    # use_azuread_auth     = true  # Use Azure AD authentication
    # snapshot             = true  # Enable state snapshots
  }
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