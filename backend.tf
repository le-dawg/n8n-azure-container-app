# ============================================================================
# Terraform Backend Configuration
# ============================================================================
#
# This configures where Terraform state is stored. For production use,
# state should be stored remotely in Azure Storage to enable:
# - Team collaboration
# - State locking (preventing concurrent modifications)
# - State history and versioning
# - Secure storage with encryption
#
# Usage:
# 1. Create backend storage account (see docs/plan.md for commands)
# 2. Update values below with your storage account details
# 3. Run: terraform init -reconfigure
#
# Multi-Environment Strategy:
# - Use different state keys for each environment:
#   - dev: envs/dev/main.tfstate
#   - stage: envs/stage/main.tfstate
#   - prod: envs/prod/main.tfstate
# - Or use Terraform workspaces with dynamic key
#
# ============================================================================

terraform {
  backend "azurerm" {
    # Backend storage account details
    # Replace these with your actual values or provide via backend config file
    # terraform init -backend-config=backend.hcl

    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstate<REPLACE_WITH_RANDOM>" # Must be globally unique
    container_name       = "tfstate"
    key                  = "envs/dev/main.tfstate"

    # Authentication
    # Uses Azure CLI authentication by default
    # For CI/CD, configure service principal or managed identity
    use_azuread_auth = true
  }
}

# ============================================================================
# Alternative: Local Backend (Dev/Testing Only)
# ============================================================================
# 
# For local development without remote state, comment out the above and
# uncomment below. NOT recommended for shared environments.
#
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }

# ============================================================================
# Backend Configuration File Example (backend.hcl)
# ============================================================================
#
# Create a file named `backend.hcl` (not committed to git) with:
#
# resource_group_name  = "tfstate-rg-prod"
# storage_account_name = "tfstateprod12345"
# container_name       = "tfstate"
# key                  = "envs/prod/main.tfstate"
#
# Then run:
# terraform init -backend-config=backend.hcl
#
