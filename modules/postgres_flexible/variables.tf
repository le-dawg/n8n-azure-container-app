# ============================================================================
# Azure PostgreSQL Flexible Server Module - Variables
# ============================================================================

# ----------------------------------------------------------------------------
# Required Variables
# ----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Name of the PostgreSQL Flexible Server. Must be globally unique."

  validation {
    condition     = can(regex("^[a-z0-9][-a-z0-9]{1,61}[a-z0-9]$", var.name))
    error_message = "Name must be 3-63 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the Azure Resource Group."
}

variable "location" {
  type        = string
  description = "Azure region for the PostgreSQL server (e.g., 'northeurope')."
}

variable "administrator_login" {
  type        = string
  description = <<-EOT
    Administrator username for the PostgreSQL server.
    
    Requirements:
    - Cannot be 'azure_superuser', 'admin', 'administrator', 'root', 'guest', 'public'
    - Cannot start with 'pg_'
    - Must be 1-63 characters
  EOT

  validation {
    condition     = !contains(["azure_superuser", "admin", "administrator", "root", "guest", "public"], var.administrator_login) && !can(regex("^pg_", var.administrator_login))
    error_message = "Administrator login cannot be a reserved name or start with 'pg_'."
  }
}

variable "administrator_password" {
  type        = string
  sensitive   = true
  description = <<-EOT
    Administrator password for the PostgreSQL server.
    
    Requirements:
    - At least 8 characters
    - Must contain characters from three of: uppercase, lowercase, numbers, special
    
    IMPORTANT: In production, use a random password generator and store in Key Vault.
    Never hard-code or commit passwords to source control.
  EOT

  validation {
    condition     = length(var.administrator_password) >= 8
    error_message = "Password must be at least 8 characters long."
  }
}

variable "databases" {
  type = map(object({
    name      = string
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.utf8")
  }))
  description = <<-EOT
    Map of databases to create on the server.
    
    Example:
    ```
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
    ```
    
    For RAG workloads with pgvector, always use UTF8 charset.
  EOT
}

# ----------------------------------------------------------------------------
# Server Configuration
# ----------------------------------------------------------------------------

variable "postgres_version" {
  type        = number
  default     = 16
  description = <<-EOT
    PostgreSQL major version.
    
    Supported versions: 12, 13, 14, 15, 16
    
    Recommendation: Use 16 for latest pgvector and FTS features.
    pgvector requires PostgreSQL 11+, but 16 offers best performance.
  EOT

  validation {
    condition     = contains([12, 13, 14, 15, 16], var.postgres_version)
    error_message = "PostgreSQL version must be 12, 13, 14, 15, or 16."
  }
}

variable "sku_name" {
  type        = string
  default     = "B_Standard_B1ms"
  description = <<-EOT
    SKU name for the PostgreSQL server.
    
    Format: <tier>_<family>_<cores>
    
    Burstable (dev/test):
    - B_Standard_B1ms: 1 vCore, 2 GB RAM (~$15/month)
    - B_Standard_B2s:  2 vCore, 4 GB RAM (~$30/month)
    
    General Purpose (production):
    - GP_Standard_D2s_v3:  2 vCore, 8 GB RAM
    - GP_Standard_D4s_v3:  4 vCore, 16 GB RAM
    
    Memory Optimized (high-performance):
    - MO_Standard_E2s_v3:  2 vCore, 16 GB RAM
    - MO_Standard_E4s_v3:  4 vCore, 32 GB RAM
    
    For RAG with pgvector (≤10 rps):
    - Dev: B_Standard_B1ms or B_Standard_B2s
    - Prod: GP_Standard_D2s_v3 (for better IOPS)
  EOT
}

variable "storage_mb" {
  type        = number
  default     = 32768
  description = <<-EOT
    Storage size in MB.
    
    Minimum: 32768 (32 GB)
    Maximum: 16777216 (16 TB)
    
    Storage is auto-growing, but set initial size based on expected data:
    - RAG with 10K documents, 1536-dim vectors: ~5-10 GB
    - Add overhead for indexes, WAL, and growth: 2-3x
    
    Recommendation for RAG dev: 32768 MB (32 GB)
    Recommendation for RAG prod: 65536 MB (64 GB) or more
  EOT

  validation {
    condition     = var.storage_mb >= 32768 && var.storage_mb <= 16777216
    error_message = "Storage must be between 32768 MB (32 GB) and 16777216 MB (16 TB)."
  }
}

variable "availability_zone" {
  type        = number
  default     = 1
  description = <<-EOT
    Availability zone for the primary server.
    
    Options: 1, 2, 3 (depends on region)
    
    For high availability, standby will be in different zone.
  EOT

  validation {
    condition     = var.availability_zone >= 1 && var.availability_zone <= 3
    error_message = "Availability zone must be 1, 2, or 3."
  }
}

variable "backup_retention_days" {
  type        = number
  default     = 7
  description = <<-EOT
    Number of days to retain backups.
    
    Range: 7-35 days
    
    Dev: 7 days (minimum)
    Prod: 14-35 days (compliance requirements)
  EOT

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 7 and 35 days."
  }
}

variable "geo_redundant_backup_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Enable geo-redundant backups for disaster recovery.
    
    When enabled, backups are replicated to a paired Azure region.
    
    Dev: false (cost optimization)
    Prod: true (disaster recovery)
    
    Note: Not available in all regions or with Burstable tier.
  EOT
}

# ----------------------------------------------------------------------------
# High Availability
# ----------------------------------------------------------------------------

variable "enable_high_availability" {
  type        = bool
  default     = false
  description = <<-EOT
    Enable zone-redundant high availability.
    
    Creates a standby replica in a different availability zone for automatic failover.
    
    Dev: false (cost optimization)
    Prod: true (99.99% SLA)
    
    Cost impact: ~2x server cost
    Not available with Burstable SKUs (use GP or MO).
  EOT
}

variable "standby_availability_zone" {
  type        = number
  default     = 2
  description = "Availability zone for the standby server (if HA enabled). Must differ from primary zone."

  validation {
    condition     = var.standby_availability_zone >= 1 && var.standby_availability_zone <= 3
    error_message = "Standby availability zone must be 1, 2, or 3."
  }
}

# ----------------------------------------------------------------------------
# Networking
# ----------------------------------------------------------------------------

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    Enable public network access.
    
    Dev: true (with firewall rules for security)
    Prod: false (use private endpoint and VNet integration)
    
    When true, use firewall_rules to restrict access.
    When false, requires delegated subnet and private endpoint setup.
  EOT
}

variable "firewall_rules" {
  type = map(object({
    name             = string
    start_ip_address = string
    end_ip_address   = string
  }))
  default     = {}
  description = <<-EOT
    Firewall rules to allow specific IP ranges.
    
    Special rule for Azure services:
    ```
    azure_services = {
      name             = "AllowAzureServices"
      start_ip_address = "0.0.0.0"
      end_ip_address   = "0.0.0.0"
    }
    ```
    
    Example with specific IPs:
    ```
    firewall_rules = {
      azure_services = {
        name             = "AllowAzureServices"
        start_ip_address = "0.0.0.0"
        end_ip_address   = "0.0.0.0"
      }
      admin_access = {
        name             = "AdminAccess"
        start_ip_address = "203.0.113.0"
        end_ip_address   = "203.0.113.255"
      }
    }
    ```
  EOT
}

# ----------------------------------------------------------------------------
# Performance Tuning
# ----------------------------------------------------------------------------

variable "shared_buffers_mb" {
  type        = number
  default     = null
  description = <<-EOT
    Shared buffer size in MB (PostgreSQL shared_buffers parameter).
    
    If null, PostgreSQL uses default (typically 25% of RAM).
    
    Guidelines:
    - 1-2 GB RAM: 256 MB
    - 4 GB RAM:   512 MB
    - 8 GB RAM:   1024 MB
    - 16 GB RAM:  2048 MB
    
    For vector search, larger shared buffers improve index cache hit rate.
  EOT
}

variable "work_mem_mb" {
  type        = number
  default     = null
  description = <<-EOT
    Memory for sort and hash operations per query (PostgreSQL work_mem).
    
    If null, PostgreSQL uses default (typically 4 MB).
    
    Guidelines for vector search:
    - Dev:  16 MB
    - Prod: 64-128 MB
    
    Note: This is per operation. High values with many connections can exhaust memory.
    Formula: work_mem * max_connections should be < total RAM.
  EOT
}

variable "maintenance_work_mem_mb" {
  type        = number
  default     = null
  description = <<-EOT
    Memory for maintenance operations like CREATE INDEX (PostgreSQL maintenance_work_mem).
    
    If null, PostgreSQL uses default (typically 64 MB).
    
    For pgvector index building:
    - Dev:  256 MB
    - Prod: 512-1024 MB
    
    Higher values speed up vector index creation significantly.
  EOT
}

variable "max_connections" {
  type        = number
  default     = null
  description = <<-EOT
    Maximum number of concurrent connections.
    
    If null, uses Azure's default based on SKU:
    - Burstable: 50-100
    - General Purpose: 100-500+
    
    For RAG workload (ACA + 2 Functions):
    - Dev:  50 (default is fine)
    - Prod: 100-200
    
    Note: Higher connections consume more memory. Ensure:
    work_mem * max_connections < total_ram
  EOT
}

variable "enable_query_logging" {
  type        = bool
  default     = false
  description = <<-EOT
    Enable query statement and duration logging.
    
    Useful for debugging, but has performance impact.
    
    Dev: true (for troubleshooting)
    Prod: false (use selective logging or monitoring instead)
  EOT
}

# ----------------------------------------------------------------------------
# RAG-Specific Configuration
# ----------------------------------------------------------------------------

variable "primary_database" {
  type        = string
  default     = "rag"
  description = <<-EOT
    Name of the primary database for RAG workload.
    
    This is used in connection string generation.
    Must exist in the databases map.
  EOT
}

# ----------------------------------------------------------------------------
# Metadata
# ----------------------------------------------------------------------------

variable "enable_telemetry" {
  type        = bool
  default     = false
  description = "Enable Azure telemetry collection (Microsoft usage data)."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Tags to apply to the PostgreSQL server resource.
    
    Best practices:
    - environment: "dev", "stage", "prod"
    - project: Project name
    - owner: Team responsible
    - cost_center: For chargeback
    - managed_by: "terraform"
    - workload: "rag", "transactional", etc.
  EOT
}
