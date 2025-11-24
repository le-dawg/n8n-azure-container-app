# ============================================================================
# Azure Container App - Generic Module
# ============================================================================
# 
# This module provides a reusable, generic Container App configuration that
# can be used for deploying any containerized application on Azure Container Apps.
# 
# Key features:
# - Flexible container configuration (single or multi-container)
# - Support for environment variables and secrets
# - Volume mounts (Azure Files, EmptyDir, Secrets)
# - Ingress configuration (public or internal)
# - Managed identity support
# - Health probe configuration
# - Scaling rules
#
# Usage:
#   See examples/ directory for common patterns
#
# ============================================================================

terraform {
  required_version = ">= 1.8, < 2.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.5"
    }
  }
}

# ============================================================================
# Container App Resource
# ============================================================================

module "container_app" {
  source  = "Azure/avm-res-app-containerapp/azurerm"
  version = "0.4.0"

  # Basic Configuration
  name                                  = var.name
  resource_group_name                   = var.resource_group_name
  container_app_environment_resource_id = var.container_app_environment_id
  enable_telemetry                      = var.enable_telemetry
  revision_mode                         = var.revision_mode
  tags                                  = var.tags

  # Template Configuration
  template = {
    containers    = var.containers
    init_containers = var.init_containers
    volumes       = var.volumes
    min_replicas  = var.min_replicas
    max_replicas  = var.max_replicas
  }

  # Managed Identity Configuration
  managed_identities = var.managed_identities

  # Ingress Configuration
  ingress = var.ingress

  # Secrets Configuration (for sensitive env vars)
  secrets = var.secrets

  # Scaling Rules (if provided)
  # Note: AVM module uses different structure, adapt as needed
  dynamic "scale" {
    for_each = var.scale_rules != null ? [1] : []
    content {
      # Custom scaling configuration
      # This will need adjustment based on actual AVM module capabilities
    }
  }
}
