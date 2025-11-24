# ============================================================================
# n8n Container App Module
# ============================================================================
#
# This module deploys n8n workflow automation platform as an Azure Container App
# with persistent storage via Azure Files.
#
# Key features:
# - n8n latest container image
# - PostgreSQL database backend (external)
# - Azure Files mount for workflow persistence
# - Managed identity for Azure resource access
# - Public ingress with HTTPS
# - Environment-specific configuration
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
# n8n Container App
# ============================================================================

module "n8n_container_app" {
  source = "../aca_app"

  name                         = var.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  enable_telemetry             = var.enable_telemetry
  revision_mode                = "Single"
  tags                         = var.tags

  min_replicas = var.min_replicas
  max_replicas = var.max_replicas

  containers = [
    {
      name   = "n8n"
      image  = var.n8n_image
      cpu    = var.cpu
      memory = var.memory

      env = concat(
        [
          # Database Configuration
          {
            name  = "DB_TYPE"
            value = "postgresdb"
          },
          {
            name  = "DB_POSTGRESDB_HOST"
            value = var.postgres_host
          },
          {
            name  = "DB_POSTGRESDB_PORT"
            value = tostring(var.postgres_port)
          },
          {
            name  = "DB_POSTGRESDB_DATABASE"
            value = var.postgres_database
          },
          {
            name  = "DB_POSTGRESDB_USER"
            value = var.postgres_user
          },
          {
            name        = "DB_POSTGRESDB_PASSWORD"
            secret_name = "db-password"
          },
          {
            name  = "DB_POSTGRESDB_SSL_ENABLED"
            value = "true"
          },

          # n8n Configuration
          {
            name  = "N8N_PROTOCOL"
            value = var.n8n_protocol
          },
          {
            name  = "N8N_PORT"
            value = tostring(var.n8n_port)
          },
          {
            name  = "WEBHOOK_URL"
            value = var.webhook_url != null ? var.webhook_url : "https://${var.name}.${var.aca_environment_default_domain}"
          },
          {
            name  = "N8N_RUNNERS_ENABLED"
            value = tostring(var.enable_runners)
          },

          # Azure Integration (for Managed Identity)
          {
            name  = "AZURE_CLIENT_ID"
            value = var.managed_identity_client_id
          },
          {
            name  = "AZURE_TENANT_ID"
            value = var.azure_tenant_id
          },

          # Workaround for Azure CLI in n8n
          {
            name  = "APPSETTING_WEBSITE_SITE_NAME"
            value = "azcli-workaround"
          },
        ],
        var.additional_env_vars
      )

      volume_mounts = var.enable_persistence ? [
        {
          name = "n8n-data"
          path = "/home/node/.n8n"
        }
      ] : []

      readiness_probes = [
        {
          transport               = "HTTP"
          port                    = var.n8n_port
          path                    = "/healthz"
          interval_seconds        = 10
          timeout                 = 5
          failure_count_threshold = 3
          success_count_threshold = 1
        }
      ]

      liveness_probes = [
        {
          transport               = "HTTP"
          port                    = var.n8n_port
          path                    = "/healthz"
          initial_delay           = 30
          interval_seconds        = 30
          timeout                 = 5
          failure_count_threshold = 3
        }
      ]
    }
  ]

  volumes = var.enable_persistence ? [
    {
      name         = "n8n-data"
      storage_type = "AzureFile"
      storage_name = var.storage_name
    }
  ] : []

  ingress = {
    external_enabled           = var.ingress_external_enabled
    allow_insecure_connections = false
    target_port                = var.n8n_port
    transport                  = "auto"
    traffic_weight = [
      {
        latest_revision = true
        percentage      = 100
      }
    ]
  }

  secrets = {
    db-password = {
      name                = "db-password"
      key_vault_secret_id = var.postgres_password_secret_id
      identity            = var.managed_identity_id
    }
  }

  managed_identities = {
    user_assigned_resource_ids = [var.managed_identity_id]
  }
}
