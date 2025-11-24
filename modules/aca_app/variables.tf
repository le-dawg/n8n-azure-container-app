# ============================================================================
# Azure Container App Module - Variables
# ============================================================================

# ----------------------------------------------------------------------------
# Required Variables
# ----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = <<-EOT
    Name of the Container App. Must be unique within the Container App Environment.
    Recommended naming convention: <service>-<environment>
    Example: "n8n-dev", "supabase-auth-prod"
  EOT

  validation {
    condition     = can(regex("^[a-z0-9][-a-z0-9]*[a-z0-9]$", var.name))
    error_message = "Name must contain only lowercase letters, numbers, and hyphens, and must start and end with alphanumeric character."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the Azure Resource Group where the Container App will be created."
}

variable "container_app_environment_id" {
  type        = string
  description = "Resource ID of the Container App Environment. All apps in same environment share networking and compute resources."
}

variable "containers" {
  type = list(object({
    name    = string
    image   = string
    cpu     = number
    memory  = string
    command = optional(list(string))
    args    = optional(list(string))
    env = optional(list(object({
      name        = string
      value       = optional(string)
      secret_name = optional(string)
    })))
    volume_mounts = optional(list(object({
      name = string
      path = string
    })))
    liveness_probes = optional(list(object({
      port                    = number
      transport               = string
      path                    = optional(string)
      initial_delay           = optional(number)
      interval_seconds        = optional(number)
      timeout                 = optional(number)
      failure_count_threshold = optional(number)
      host                    = optional(string)
    })))
    readiness_probes = optional(list(object({
      port                    = number
      transport               = string
      path                    = optional(string)
      interval_seconds        = optional(number)
      timeout                 = optional(number)
      failure_count_threshold = optional(number)
      success_count_threshold = optional(number)
      host                    = optional(string)
    })))
    startup_probe = optional(list(object({
      port                    = number
      transport               = string
      path                    = optional(string)
      interval_seconds        = optional(number)
      timeout                 = optional(number)
      failure_count_threshold = optional(number)
      host                    = optional(string)
    })))
  }))
  description = <<-EOT
    List of containers to run in this Container App.
    
    Fields:
    - name: Container name (must be unique within the app)
    - image: Full container image path (e.g., "docker.io/n8nio/n8n:latest")
    - cpu: CPU cores (fractional values supported, e.g., 0.25, 0.5, 1.0)
    - memory: Memory allocation (e.g., "0.5Gi", "1Gi", "2Gi")
    - command: Override container entrypoint (optional)
    - args: Override container command arguments (optional)
    - env: Environment variables (use secret_name for sensitive values)
    - volume_mounts: Mount points for volumes
    - liveness_probes: List of health checks to restart unhealthy containers
    - readiness_probes: List of health checks to route traffic only to ready containers
    - startup_probe: List of health checks for slow-starting containers
    
    Note: Probes must be provided as lists, even for a single probe.
    
    Example:
    ```
    containers = [
      {
        name   = "web"
        image  = "nginx:latest"
        cpu    = 0.25
        memory = "0.5Gi"
        env = [
          { name = "PORT", value = "8080" },
          { name = "API_KEY", secret_name = "api-key" }
        ]
        readiness_probes = [
          {
            port      = 80
            transport = "HTTP"
            path      = "/health"
          }
        ]
      }
    ]
    ```
  EOT
}

# ----------------------------------------------------------------------------
# Optional Variables
# ----------------------------------------------------------------------------

variable "init_containers" {
  type = list(object({
    name    = string
    image   = string
    cpu     = optional(number)
    memory  = optional(string)
    command = optional(list(string))
    args    = optional(list(string))
    env = optional(list(object({
      name        = string
      value       = optional(string)
      secret_name = optional(string)
    })))
    volume_mounts = optional(list(object({
      name = string
      path = string
    })))
  }))
  default     = []
  description = <<-EOT
    Init containers run before main containers start, typically for setup tasks.
    They run sequentially and must complete successfully before main containers start.
  EOT
}

variable "volumes" {
  type = list(object({
    name          = string
    storage_type  = optional(string)
    storage_name  = optional(string)
    mount_options = optional(string)
  }))
  default     = []
  description = <<-EOT
    Volumes that can be mounted by containers.
    
    Types:
    - AzureFile: Azure Files share (persistent, multi-read/write)
    - EmptyDir: Temporary storage (lifecycle tied to revision)
    - Secret: Kubernetes secrets (for config files)
    
    Example:
    ```
    volumes = [
      {
        name         = "data"
        storage_type = "AzureFile"
        storage_name = "myshare"  # Must match Container App Environment storage name
      },
      {
        name         = "cache"
        storage_type = "EmptyDir"
      }
    ]
    ```
  EOT
}

variable "min_replicas" {
  type        = number
  default     = 1
  description = "Minimum number of replicas. Set to 0 to allow scale-to-zero (requires scale rules)."

  validation {
    condition     = var.min_replicas >= 0
    error_message = "Minimum replicas must be >= 0."
  }
}

variable "max_replicas" {
  type        = number
  default     = 1
  description = "Maximum number of replicas for autoscaling. Set > min_replicas to enable scaling."

  validation {
    condition     = var.max_replicas >= 1
    error_message = "Maximum replicas must be >= 1."
  }
}

variable "ingress" {
  type = object({
    allow_insecure_connections = optional(bool, false)
    client_certificate_mode    = optional(string, "ignore")
    external_enabled           = optional(bool, true)
    target_port                = number
    transport                  = optional(string, "auto")
    traffic_weight = optional(list(object({
      latest_revision = optional(bool)
      revision_suffix = optional(string)
      percentage      = number
      label           = optional(string)
    })))
    custom_domain = optional(object({
      name                     = string
      certificate_id           = string
      certificate_binding_type = optional(string, "SniEnabled")
    }))
  })
  default     = null
  description = <<-EOT
    Ingress configuration for exposing the app via HTTP/HTTPS.
    
    If null, the app is not exposed and can only be accessed from within the environment.
    
    Fields:
    - allow_insecure_connections: Allow HTTP traffic (not recommended for prod)
    - client_certificate_mode: "ignore", "accept", or "require"
    - external_enabled: true = internet-facing, false = internal only
    - target_port: Port the container listens on
    - transport: "auto", "http", or "http2"
    - traffic_weight: Traffic splitting config (for blue/green deployments)
    - custom_domain: Optional custom domain configuration
    
    Example:
    ```
    ingress = {
      external_enabled = true
      target_port      = 8080
      traffic_weight = [
        { latest_revision = true, percentage = 100 }
      ]
    }
    ```
  EOT
}

variable "secrets" {
  type = map(object({
    name                = string
    value               = optional(string)
    key_vault_secret_id = optional(string)
    identity            = optional(string)
  }))
  default     = {}
  description = <<-EOT
    Secrets for sensitive environment variables.
    
    Secrets can be sourced from:
    1. Direct value (not recommended, use for dev only)
    2. Azure Key Vault (recommended for prod)
    
    Usage in container env vars:
    ```
    env = [
      { name = "DB_PASSWORD", secret_name = "db-password" }
    ]
    ```
    
    Example:
    ```
    secrets = {
      db-password = {
        name                = "db-password"
        key_vault_secret_id = "<KEY_VAULT_SECRET_ID>"
        identity            = "<MANAGED_IDENTITY_ID>"
      }
    }
    ```
  EOT
}

variable "managed_identities" {
  type = object({
    system_assigned            = optional(bool, false)
    user_assigned_resource_ids = optional(list(string), [])
  })
  default     = null
  description = <<-EOT
    Managed identity configuration for Azure resource authentication.
    
    Types:
    - system_assigned: Azure-managed identity (lifecycle tied to Container App)
    - user_assigned: Pre-created identity (can be shared across resources)
    
    Use managed identities to:
    - Access Key Vault secrets
    - Connect to databases
    - Call Azure APIs
    - Access storage accounts
    
    Example:
    ```
    managed_identities = {
      system_assigned = true
      user_assigned_resource_ids = [
        "<USER_ASSIGNED_IDENTITY_ID>"
      ]
    }
    ```
  EOT
}

variable "scale_rules" {
  type = list(object({
    name     = string
    type     = string # "http", "azure-queue", "cpu", "memory", etc.
    metadata = map(string)
  }))
  default     = null
  description = <<-EOT
    Custom autoscaling rules (beyond min/max replicas).
    
    Types:
    - http: Scale based on concurrent requests
    - cpu: Scale based on CPU utilization
    - memory: Scale based on memory utilization
    - azure-queue: Scale based on Azure Storage Queue length
    - Custom KEDA scalers
    
    Example:
    ```
    scale_rules = [
      {
        name = "http-scaler"
        type = "http"
        metadata = {
          concurrentRequests = "10"
        }
      }
    ]
    ```
    
    Note: This feature may require adaptation based on AVM module capabilities.
  EOT
}

variable "revision_mode" {
  type        = string
  default     = "Single"
  description = <<-EOT
    Revision mode for the Container App.
    
    - "Single": Only one revision active at a time (rolling updates)
    - "Multiple": Multiple revisions can coexist (blue/green deployments)
    
    Use "Single" for most cases. Use "Multiple" for advanced deployment strategies.
  EOT

  validation {
    condition     = contains(["Single", "Multiple"], var.revision_mode)
    error_message = "Revision mode must be 'Single' or 'Multiple'."
  }
}

variable "enable_telemetry" {
  type        = bool
  default     = false
  description = "Enable Azure telemetry collection (Microsoft usage data, not application logs)."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Tags to apply to the Container App resource.
    
    Best practices:
    - environment: "dev", "stage", "prod"
    - project: Project name
    - owner: Team or individual responsible
    - cost_center: For chargeback
    - managed_by: "terraform"
  EOT
}
