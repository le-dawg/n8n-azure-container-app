# ============================================================================
# n8n Module - Variables
# ============================================================================

# ----------------------------------------------------------------------------
# Required Variables
# ----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Name of the n8n Container App."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the Azure Resource Group."
}

variable "container_app_environment_id" {
  type        = string
  description = "Resource ID of the Container App Environment."
}

variable "postgres_host" {
  type        = string
  description = "PostgreSQL server hostname (FQDN)."
}

variable "postgres_user" {
  type        = string
  description = "PostgreSQL username."
}

variable "postgres_password_secret_id" {
  type        = string
  description = "Azure Key Vault secret ID containing the PostgreSQL password."
}

variable "managed_identity_id" {
  type        = string
  description = "Resource ID of the user-assigned managed identity."
}

variable "managed_identity_client_id" {
  type        = string
  description = "Client ID of the user-assigned managed identity."
}

variable "azure_tenant_id" {
  type        = string
  description = "Azure AD tenant ID."
}

variable "aca_environment_default_domain" {
  type        = string
  description = "Default domain of the Container App Environment (for generating webhook URL)."
}

# ----------------------------------------------------------------------------
# Optional Variables - n8n Configuration
# ----------------------------------------------------------------------------

variable "n8n_image" {
  type        = string
  default     = "docker.io/n8nio/n8n:latest"
  description = <<-EOT
    n8n container image to deploy.
    
    Options:
    - latest: Latest stable release
    - Specific version: n8nio/n8n:1.0.0
    - Self-hosted registry: myregistry.azurecr.io/n8n:custom
  EOT
}

variable "postgres_port" {
  type        = number
  default     = 5432
  description = "PostgreSQL server port."
}

variable "postgres_database" {
  type        = string
  default     = "n8n"
  description = "PostgreSQL database name for n8n."
}

variable "n8n_protocol" {
  type        = string
  default     = "http"
  description = <<-EOT
    Protocol for n8n web interface.
    
    Use "http" when behind ingress (TLS termination at ingress level).
    Use "https" only if n8n needs to handle TLS directly.
  EOT

  validation {
    condition     = contains(["http", "https"], var.n8n_protocol)
    error_message = "Protocol must be 'http' or 'https'."
  }
}

variable "n8n_port" {
  type        = number
  default     = 5678
  description = "Port that n8n listens on inside the container."
}

variable "webhook_url" {
  type        = string
  default     = null
  description = <<-EOT
    Public webhook URL for n8n workflows.
    
    If null, will be automatically generated from Container App FQDN.
    Override this if using custom domain or reverse proxy.
  EOT
}

variable "enable_runners" {
  type        = bool
  default     = true
  description = <<-EOT
    Enable n8n task runners for code execution isolation.
    
    Recommended: true for security and stability.
  EOT
}

variable "enable_persistence" {
  type        = bool
  default     = true
  description = <<-EOT
    Enable persistent storage via Azure Files.
    
    When true, n8n workflows, credentials, and settings are persisted across restarts.
    When false, n8n runs in ephemeral mode (not recommended for production).
  EOT
}

variable "storage_name" {
  type        = string
  default     = "n8nconfig"
  description = <<-EOT
    Name of the Container App Environment storage (Azure Files).
    
    Must match the storage name configured in the Container App Environment.
  EOT
}

variable "additional_env_vars" {
  type = list(object({
    name        = string
    value       = optional(string)
    secret_name = optional(string)
  }))
  default     = []
  description = <<-EOT
    Additional environment variables for n8n.
    
    Common variables:
    - N8N_BASIC_AUTH_ACTIVE: Enable basic auth
    - N8N_BASIC_AUTH_USER: Basic auth username
    - N8N_BASIC_AUTH_PASSWORD: Basic auth password (use secret_name)
    - N8N_ENCRYPTION_KEY: Encryption key for credentials (use secret_name)
    - GENERIC_TIMEZONE: Set timezone (e.g., "Europe/Oslo")
    - N8N_LOG_LEVEL: Log level (info, debug, warn, error)
    
    Example:
    ```
    additional_env_vars = [
      {
        name  = "N8N_BASIC_AUTH_ACTIVE"
        value = "true"
      },
      {
        name        = "N8N_BASIC_AUTH_PASSWORD"
        secret_name = "n8n-auth-password"
      }
    ]
    ```
  EOT
}

# ----------------------------------------------------------------------------
# Optional Variables - Resource Sizing
# ----------------------------------------------------------------------------

variable "cpu" {
  type        = number
  default     = 0.25
  description = <<-EOT
    CPU cores for n8n container.
    
    Recommendations:
    - Dev/test: 0.25
    - Small prod (≤10 workflows): 0.5
    - Medium prod: 1.0
    - Large prod: 2.0+
  EOT
}

variable "memory" {
  type        = string
  default     = "0.5Gi"
  description = <<-EOT
    Memory allocation for n8n container.
    
    Recommendations:
    - Dev/test: 0.5Gi
    - Small prod: 1Gi
    - Medium prod: 2Gi
    - Large prod: 4Gi+
  EOT
}

variable "min_replicas" {
  type        = number
  default     = 1
  description = <<-EOT
    Minimum number of n8n replicas.
    
    Recommendations:
    - Dev/test: 1
    - Prod: 2 (for high availability)
    
    Note: n8n is primarily single-instance. Multiple replicas require
    additional configuration for queue-based workflow execution.
  EOT
}

variable "max_replicas" {
  type        = number
  default     = 1
  description = <<-EOT
    Maximum number of n8n replicas.
    
    For most use cases, keep at 1 unless you've configured n8n for
    horizontal scaling with queue mode.
  EOT
}

# ----------------------------------------------------------------------------
# Optional Variables - Networking
# ----------------------------------------------------------------------------

variable "ingress_external_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    Enable external (internet-facing) ingress.
    
    true: n8n accessible from internet (configure auth!)
    false: n8n only accessible from within Container App Environment
  EOT
}

# ----------------------------------------------------------------------------
# Metadata
# ----------------------------------------------------------------------------

variable "enable_telemetry" {
  type        = bool
  default     = false
  description = "Enable Azure telemetry collection."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the n8n Container App."
}
