# ============================================================================
# Azure PostgreSQL Flexible Server Module with pgvector
# ============================================================================
#
# This module provisions an Azure Database for PostgreSQL Flexible Server
# optimized for RAG workloads with pgvector support for embeddings storage
# and full-text search capabilities for BM25 hybrid search.
#
# Key features:
# - pgvector extension for vector embeddings
# - Full-text search extensions (pg_trgm, unaccent)
# - Configurable SKU and storage
# - Firewall rules for Azure services and specific IPs/subnets
# - High availability options
# - Backup configuration
# - Optional private endpoint support (future)
#
# ============================================================================

terraform {
  required_version = ">= 1.8, < 2.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

# ============================================================================
# PostgreSQL Flexible Server
# ============================================================================

module "postgresql" {
  source  = "Azure/avm-res-dbforpostgresql-flexibleserver/azurerm"
  version = "0.1.4"

  # Basic Configuration
  location               = var.location
  name                   = var.name
  resource_group_name    = var.resource_group_name
  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password
  enable_telemetry       = var.enable_telemetry
  tags                   = var.tags

  # Server Configuration
  server_version = var.postgres_version
  sku_name       = var.sku_name
  storage_mb     = var.storage_mb
  zone           = var.availability_zone

  # Network Configuration
  # Note: For dev, using public access with firewall rules
  # For prod, consider delegated subnet for private access
  public_network_access_enabled = var.public_network_access_enabled

  # High Availability Configuration
  high_availability = var.enable_high_availability ? {
    mode                      = "ZoneRedundant"
    standby_availability_zone = var.standby_availability_zone
  } : null

  # Backup Configuration
  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  # Database Configuration
  databases = var.databases

  # Firewall Rules
  firewall_rules = var.firewall_rules

  # Server Configuration Parameters
  # These enable pgvector and other extensions needed for RAG
  configurations = {
    # Enable required extensions (requires server restart)
    # Note: Some extensions may require allowlisting in Azure
    "azure.extensions" = {
      value = "VECTOR,PG_TRGM,UNACCENT,PG_STAT_STATEMENTS"
    }

    # Shared preload libraries (for extensions that need it)
    "shared_preload_libraries" = {
      value = "pg_stat_statements"
    }

    # Memory and performance tuning for vector operations
    # Adjust based on SKU size
    "shared_buffers" = {
      value = var.shared_buffers_mb != null ? "${var.shared_buffers_mb}MB" : null
    }

    "work_mem" = {
      value = var.work_mem_mb != null ? "${var.work_mem_mb}MB" : null
    }

    "maintenance_work_mem" = {
      value = var.maintenance_work_mem_mb != null ? "${var.maintenance_work_mem_mb}MB" : null
    }

    # Increase max connections if needed
    "max_connections" = {
      value = var.max_connections != null ? tostring(var.max_connections) : null
    }

    # Enable query logging for troubleshooting (disable in prod for performance)
    "log_statement" = {
      value = var.enable_query_logging ? "all" : "none"
    }

    "log_duration" = {
      value = var.enable_query_logging ? "on" : "off"
    }
  }
}

# ============================================================================
# Connection String Output (for convenience)
# ============================================================================

locals {
  connection_string = "host=${module.postgresql.fqdn} port=5432 dbname=${var.primary_database} user=${var.administrator_login} password=${var.administrator_password} sslmode=require"
}
