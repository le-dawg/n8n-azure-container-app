# ============================================================================
# Azure-Native RAG Stack - Main Configuration
# ============================================================================
#
# This is the root Terraform configuration for deploying a complete
# Azure-native RAG (Retrieval-Augmented Generation) stack including:
# - n8n workflow automation
# - PostgreSQL with pgvector for embeddings
# - (Future) Supabase self-hosted stack
# - (Future) Azure Functions for ingestion and BM25/hybrid retrieval
# - (Future) Azure AI Foundry rerankers
# - (Future) Azure Static Web App frontend
#
# See docs/plan.md for deployment instructions.
# See docs/adr/0001-architecture.md for architecture decisions.
#
# ============================================================================

# ============================================================================
# Naming Convention
# ============================================================================

module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.0"
}

# ============================================================================
# Resource Group
# ============================================================================

resource "azurerm_resource_group" "this" {
  location = var.location
  name     = module.naming.resource_group.name_unique
  tags     = merge(var.tags, { environment = var.environment })
}

# ============================================================================
# Data Sources
# ============================================================================

data "azurerm_client_config" "current" {
  # Current Azure client configuration (tenant, subscription, object ID)
}

# ============================================================================
# Managed Identity
# ============================================================================
# User-assigned managed identity used by Container Apps and Functions
# for accessing Azure resources (Key Vault, Storage, etc.)

resource "azurerm_user_assigned_identity" "this" {
  location            = azurerm_resource_group.this.location
  name                = module.naming.user_assigned_identity.name_unique
  resource_group_name = azurerm_resource_group.this.name
  tags                = merge(var.tags, { environment = var.environment })
}

# ============================================================================
# PostgreSQL Password Generation
# ============================================================================

resource "random_password" "postgres" {
  length           = 16
  override_special = "_%@"
  special          = true
}

# ============================================================================
# PostgreSQL Flexible Server with pgvector
# ============================================================================

module "postgresql" {
  source = "./modules/postgres_flexible"

  name                = module.naming.postgresql_server.name_unique
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  administrator_login    = "psqladmin"
  administrator_password = random_password.postgres.result

  postgres_version = var.postgres_version
  sku_name         = var.postgres_sku_name
  storage_mb       = var.postgres_storage_mb

  backup_retention_days = var.postgres_backup_retention_days

  # Enable pgvector and full-text search extensions
  # These are configured in the module's configurations block

  databases = {
    n8n = {
      name      = "n8n"
      charset   = "UTF8"
      collation = "en_US.utf8"
    }
    rag = {
      name      = "rag"
      charset   = "UTF8"
      collation = "en_US.utf8"
    }
  }

  primary_database = "rag"

  # Allow Azure services to access the database
  firewall_rules = {
    azure_services = {
      name             = "AllowAzureServices"
      start_ip_address = "0.0.0.0"
      end_ip_address   = "0.0.0.0"
    }
  }

  enable_telemetry = var.enable_telemetry
  tags             = merge(var.tags, { environment = var.environment })
}

# ============================================================================
# Azure Key Vault
# ============================================================================

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.0"

  location                      = azurerm_resource_group.this.location
  name                          = module.naming.key_vault.name_unique
  resource_group_name           = azurerm_resource_group.this.name
  enable_telemetry              = var.enable_telemetry
  public_network_access_enabled = true
  tags                          = merge(var.tags, { environment = var.environment })
  tenant_id                     = data.azurerm_client_config.current.tenant_id

  # Store database password and OpenAI key
  secrets = {
    psqladmin-password = {
      name = "psqladmin-password"
    }
    openai-key = {
      name = "openai-key"
    }
  }

  secrets_value = {
    psqladmin-password = random_password.postgres.result
    openai-key         = module.openai.primary_access_key
  }

  # RBAC for accessing secrets
  role_assignments = {
    deployment_user_kv_admin = {
      role_definition_id_or_name = "Key Vault Administrator"
      principal_id               = data.azurerm_client_config.current.object_id
    }
    container_app_kv_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = azurerm_user_assigned_identity.this.principal_id
    }
  }

  wait_for_rbac_before_secret_operations = {
    create = "60s"
  }

  network_acls = {
    bypass         = "AzureServices"
    default_action = "Allow"
  }
}

# ============================================================================
# Azure OpenAI
# ============================================================================

module "openai" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.7.0"

  location            = azurerm_resource_group.this.location
  name                = module.naming.cognitive_account.name_unique
  resource_group_name = azurerm_resource_group.this.name
  enable_telemetry    = var.enable_telemetry
  kind                = "OpenAI"
  sku_name            = "S0"
  tags                = merge(var.tags, { environment = var.environment })

  cognitive_deployments = {
    "gpt-4o-mini" = {
      name = "gpt-4o-mini"
      model = {
        format  = "OpenAI"
        name    = "gpt-4o-mini"
        version = "2024-07-18"
      }
      scale = {
        type     = "GlobalStandard"
        capacity = 8
      }
    }
  }
}

# ============================================================================
# Azure Storage Account
# ============================================================================

module "storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.5.0"

  location                      = azurerm_resource_group.this.location
  name                          = module.naming.storage_account.name_unique
  resource_group_name           = azurerm_resource_group.this.name
  account_replication_type      = "LRS"
  account_tier                  = "Standard"
  account_kind                  = "StorageV2"
  enable_telemetry              = var.enable_telemetry
  https_traffic_only_enabled    = true
  min_tls_version               = "TLS1_2"
  shared_access_key_enabled     = true
  public_network_access_enabled = true
  tags                          = merge(var.tags, { environment = var.environment })

  network_rules = null

  # File share for n8n persistence
  shares = {
    n8nconfig = {
      name        = "n8nconfig"
      quota       = 2
      access_tier = "Hot"
    }
  }
}

# ============================================================================
# Azure Container Apps Environment
# ============================================================================

resource "azurerm_container_app_environment" "this" {
  location            = azurerm_resource_group.this.location
  name                = module.naming.container_app_environment.name_unique
  resource_group_name = azurerm_resource_group.this.name
  tags                = merge(var.tags, { environment = var.environment })
}

# Container App Environment Storage (Azure Files for n8n)
resource "azurerm_container_app_environment_storage" "this" {
  name                         = "n8nconfig"
  access_key                   = module.storage.resource.primary_access_key
  access_mode                  = "ReadWrite"
  account_name                 = module.storage.name
  container_app_environment_id = azurerm_container_app_environment.this.id
  share_name                   = "n8nconfig"
}

# ============================================================================
# n8n Container App
# ============================================================================

module "n8n" {
  source = "./modules/n8n"

  name                         = "${module.naming.container_app.name_unique}-n8n"
  resource_group_name          = azurerm_resource_group.this.name
  container_app_environment_id = azurerm_container_app_environment.this.id

  # PostgreSQL Configuration
  postgres_host               = module.postgresql.fqdn
  postgres_user               = "psqladmin"
  postgres_database           = "n8n"
  postgres_password_secret_id = module.key_vault.secrets_resource_ids["psqladmin-password"].id

  # Managed Identity
  managed_identity_id        = azurerm_user_assigned_identity.this.id
  managed_identity_client_id = azurerm_user_assigned_identity.this.client_id
  azure_tenant_id            = data.azurerm_client_config.current.tenant_id

  # Container App Environment
  aca_environment_default_domain = azurerm_container_app_environment.this.default_domain

  # Persistence
  enable_persistence = true
  storage_name       = azurerm_container_app_environment_storage.this.name

  # Resource Sizing (dev defaults)
  cpu    = 0.25
  memory = "0.5Gi"

  enable_telemetry = var.enable_telemetry
  tags             = merge(var.tags, { environment = var.environment })
}

# ============================================================================
# MCP Container App (Optional)
# ============================================================================
# Deploys the MCP (Model Context Protocol) server for n8n integration

module "container_app_mcp" {
  count = var.deploy_mcp ? 1 : 0

  source  = "Azure/avm-res-app-containerapp/azurerm"
  version = "0.4.0"

  name                                  = "${module.naming.container_app.name_unique}-mcp"
  resource_group_name                   = azurerm_resource_group.this.name
  container_app_environment_resource_id = azurerm_container_app_environment.this.id
  enable_telemetry                      = var.enable_telemetry
  revision_mode                         = "Single"
  tags                                  = merge(var.tags, { environment = var.environment })

  template = {
    containers = [
      {
        name   = "mcp-server"
        memory = "0.5Gi"
        cpu    = 0.25
        image  = "docker.io/mcp/azure:latest"

        env = [
          {
            name  = "AZMCP_TRANSPORT"
            value = "sse"
          },
          {
            name  = "AZURE_MCP_INCLUDE_PRODUCTION_CREDENTIALS"
            value = "true"
          },
          {
            name  = "AZURE_TENANT_ID"
            value = data.azurerm_client_config.current.tenant_id
          },
          {
            name  = "AZURE_CLIENT_ID"
            value = azurerm_user_assigned_identity.this.client_id
          }
        ]
      },
      {
        name   = "nginx"
        memory = "0.5Gi"
        cpu    = 0.25
        image  = "nginx:latest"

        command = [
          "sh", "-c",
          <<EOT
echo "server {
  listen 80;
  location / {
    proxy_http_version          1.1;
    proxy_buffering             off;
    gzip                        off;
    chunked_transfer_encoding   off;

    proxy_set_header            Connection '';

    proxy_pass http://localhost:5008;
  }
}" > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'
EOT
        ]
      }
    ]
  }

  managed_identities = {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.this.id]
  }

  ingress = {
    allow_insecure_connections = false
    client_certificate_mode    = "ignore"
    external_enabled           = true
    target_port                = 80
    traffic_weight = [
      {
        latest_revision = true
        percentage      = 100
      }
    ]
  }
}

# ============================================================================
# Outputs
# ============================================================================
# See outputs.tf for output definitions
