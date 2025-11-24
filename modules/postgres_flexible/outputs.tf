# ============================================================================
# Azure PostgreSQL Flexible Server Module - Outputs
# ============================================================================

output "id" {
  description = "Resource ID of the PostgreSQL Flexible Server."
  value       = module.postgresql.resource_id
}

output "name" {
  description = "Name of the PostgreSQL Flexible Server."
  value       = module.postgresql.name
}

output "fqdn" {
  description = "Fully qualified domain name of the PostgreSQL server."
  value       = module.postgresql.fqdn
}

output "connection_string" {
  description = <<-EOT
    PostgreSQL connection string (includes password - sensitive).
    
    Format: host=<fqdn> port=5432 dbname=<database> user=<admin> password=<password> sslmode=require
    
    Use this for local testing only. In production, store connection details in Key Vault.
  EOT
  value       = local.connection_string
  sensitive   = true
}

output "administrator_login" {
  description = "Administrator username for the PostgreSQL server."
  value       = var.administrator_login
}

output "database_names" {
  description = "List of database names created on the server."
  value       = [for db in var.databases : db.name]
}

output "server_version" {
  description = "PostgreSQL server version."
  value       = var.postgres_version
}

output "sku_name" {
  description = "SKU name of the PostgreSQL server."
  value       = var.sku_name
}

output "storage_mb" {
  description = "Storage size in MB."
  value       = var.storage_mb
}

output "high_availability_enabled" {
  description = "Whether high availability is enabled."
  value       = var.enable_high_availability
}

output "public_network_access_enabled" {
  description = "Whether public network access is enabled."
  value       = var.public_network_access_enabled
}

output "firewall_rules" {
  description = "Firewall rules configured on the server."
  value = {
    for k, v in var.firewall_rules : k => {
      name  = v.name
      start = v.start_ip_address
      end   = v.end_ip_address
    }
  }
}

output "backup_retention_days" {
  description = "Number of days backups are retained."
  value       = var.backup_retention_days
}

output "resource" {
  description = "Full PostgreSQL Flexible Server resource object (for advanced use cases)."
  value       = module.postgresql.resource
  sensitive   = true
}

# ============================================================================
# Connection Information for Different Components
# ============================================================================

output "jdbc_url" {
  description = "JDBC connection URL for Java applications."
  value       = "jdbc:postgresql://${module.postgresql.fqdn}:5432/${var.primary_database}?sslmode=require"
}

output "psycopg2_dsn" {
  description = "psycopg2 DSN for Python applications (without password)."
  value       = "host=${module.postgresql.fqdn} port=5432 dbname=${var.primary_database} user=${var.administrator_login} sslmode=require"
}

output "sqlalchemy_url" {
  description = "SQLAlchemy connection URL for Python applications (without password)."
  value       = "postgresql://${var.administrator_login}@${module.postgresql.fqdn}:5432/${var.primary_database}?sslmode=require"
}

output "node_pg_config" {
  description = "Configuration object for Node.js pg library."
  value = {
    host     = module.postgresql.fqdn
    port     = 5432
    database = var.primary_database
    user     = var.administrator_login
    ssl      = true
  }
}

# ============================================================================
# Extension Information
# ============================================================================

output "enabled_extensions" {
  description = "List of PostgreSQL extensions enabled via server configuration."
  value       = ["vector", "pg_trgm", "unaccent", "pg_stat_statements"]
}

output "extension_setup_sql" {
  description = <<-EOT
    SQL commands to create extensions in your database.
    
    Run these after connecting to your database with psql or another client:
    ```
    psql "$(terraform output -raw connection_string)"
    ```
  EOT
  value       = <<-EOT
-- Enable pgvector for embedding storage
CREATE EXTENSION IF NOT EXISTS vector;

-- Enable trigram similarity for BM25/fuzzy search
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Enable unaccent for better text search (removes diacritics)
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Enable query statistics (for performance monitoring)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Verify extensions
SELECT extname, extversion FROM pg_extension;
EOT
}

output "performance_tuning_notes" {
  description = "PostgreSQL configuration parameters set for RAG performance."
  value = {
    shared_buffers_mb       = var.shared_buffers_mb
    work_mem_mb             = var.work_mem_mb
    maintenance_work_mem_mb = var.maintenance_work_mem_mb
    max_connections         = var.max_connections
    note                    = "These settings optimize for vector search and index building. Adjust based on actual workload."
  }
}
