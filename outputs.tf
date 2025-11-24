# ============================================================================
# Terraform Outputs
# ============================================================================

# ============================================================================
# Resource Group
# ============================================================================

output "resource_group_name" {
  description = "Name of the resource group containing all resources."
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "Azure region where resources are deployed."
  value       = azurerm_resource_group.this.location
}

# ============================================================================
# n8n Outputs
# ============================================================================

output "n8n_fqdn_url" {
  description = "HTTPS URL to access the n8n web interface."
  value       = module.n8n.fqdn_url
}

output "n8n_webhook_url" {
  description = "Webhook URL for n8n workflows."
  value       = module.n8n.webhook_url
}

# ============================================================================
# MCP Outputs (Optional)
# ============================================================================

output "mcp_endpoint_sse" {
  description = "SSE endpoint of the MCP Server (if deployed)."
  value       = var.deploy_mcp ? "${module.container_app_mcp[0].fqdn_url}/sse" : null
}

# ============================================================================
# PostgreSQL Outputs
# ============================================================================

output "postgres_fqdn" {
  description = "Fully qualified domain name of the PostgreSQL server."
  value       = module.postgresql.fqdn
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string (includes password - sensitive)."
  value       = module.postgresql.connection_string
  sensitive   = true
}

output "postgres_databases" {
  description = "List of databases created on the PostgreSQL server."
  value       = module.postgresql.database_names
}

# ============================================================================
# OpenAI Outputs
# ============================================================================

output "openai_endpoint" {
  description = "Azure OpenAI endpoint URL."
  value       = module.openai.endpoint
}

output "openai_resource_name" {
  description = "Azure OpenAI resource name."
  value       = module.openai.resource.custom_subdomain_name
}

output "openai_deployment_name" {
  description = "Name of the OpenAI deployment (GPT-4o-mini)."
  value       = module.openai.resource_cognitive_deployment["gpt-4o-mini"].name
}

output "openai_api_version" {
  description = "Azure OpenAI API version to use in n8n credentials."
  value       = "2025-03-01-preview"
}

output "openai_key_secret_url" {
  description = "Azure Key Vault secret URL containing the OpenAI API key."
  value       = module.key_vault.secrets["openai-key"].versionless_id
}

# ============================================================================
# Key Vault Outputs
# ============================================================================

output "key_vault_name" {
  description = "Name of the Azure Key Vault."
  value       = module.key_vault.name
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault."
  value       = module.key_vault.resource_id # Using resource_id instead of resource.vault_uri
}

# ============================================================================
# Storage Outputs
# ============================================================================

output "storage_account_name" {
  description = "Name of the Azure Storage Account."
  value       = module.storage.name
}

# ============================================================================
# Container App Environment Outputs
# ============================================================================

output "container_app_environment_id" {
  description = "Resource ID of the Container App Environment."
  value       = azurerm_container_app_environment.this.id
}

output "container_app_environment_default_domain" {
  description = "Default domain of the Container App Environment."
  value       = azurerm_container_app_environment.this.default_domain
}

# ============================================================================
# Managed Identity Outputs
# ============================================================================

output "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity."
  value       = azurerm_user_assigned_identity.this.principal_id
}

# ============================================================================
# RAG Configuration Outputs
# ============================================================================

output "embedding_dimension" {
  description = "Embedding vector dimension configured for RAG."
  value       = var.embedding_dimension
}

output "vector_index_type" {
  description = "pgvector index type configured for RAG."
  value       = var.vector_index_type
}

output "hybrid_alpha" {
  description = "Hybrid search weight (alpha) configured for RAG."
  value       = var.hybrid_alpha
}

output "fusion_strategy" {
  description = "Fusion strategy configured for hybrid search."
  value       = var.fusion_strategy
}
