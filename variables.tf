# ============================================================================
# Core Configuration Variables
# ============================================================================

variable "environment" {
  type        = string
  default     = "dev"
  description = <<-EOT
    Environment name (dev, stage, prod).
    
    This is used for naming and tagging resources, and for selecting
    environment-specific configurations.
  EOT

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "Environment must be one of: dev, stage, prod."
  }
}

variable "location" {
  type        = string
  default     = "northeurope"
  description = <<-EOT
    Azure region for resource deployment.
    
    Per requirements: All resources must be in EU regions, primarily northeurope.
    Fallback to westeurope only if specific services unavailable in northeurope.
  EOT
}

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID where all resources will be deployed."
}

variable "enable_telemetry" {
  type        = bool
  default     = false
  description = <<-EOT
    Enable Azure telemetry collection (Microsoft usage data).
    See https://aka.ms/avm/telemetryinfo for details.
  EOT
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Common tags to apply to all resources.
    
    Recommended tags:
    - environment: Environment name
    - project: Project name
    - managed_by: "terraform"
    - cost_center: For chargeback
  EOT
}

# ============================================================================
# Feature Flags
# ============================================================================

variable "deploy_mcp" {
  type        = bool
  default     = false
  description = "Deploy MCP (Model Context Protocol) container app for n8n integration."
}

variable "enable_supabase_studio" {
  type        = bool
  default     = false
  description = <<-EOT
    Deploy Supabase Studio (web UI) container.
    
    Recommended: false for production (cost optimization and security).
    Set to true for dev if you need the Supabase admin UI.
  EOT
}

variable "enable_supabase_storage" {
  type        = bool
  default     = false
  description = <<-EOT
    Deploy Supabase Storage service.
    
    Only enable if you need Supabase's object storage semantics.
    For document storage, consider using Azure Blob Storage directly.
  EOT
}

variable "enable_reranker" {
  type        = bool
  default     = true
  description = "Deploy Azure AI Foundry reranker endpoints (Cohere and BGE)."
}

# ============================================================================
# Database Configuration
# ============================================================================

variable "postgres_sku_name" {
  type        = string
  default     = "B_Standard_B1ms"
  description = <<-EOT
    PostgreSQL Flexible Server SKU.
    
    Dev: B_Standard_B1ms (1 vCore, 2 GB RAM)
    Prod: GP_Standard_D2s_v3 (2 vCore, 8 GB RAM) or higher
  EOT
}

variable "postgres_version" {
  type        = number
  default     = 16
  description = "PostgreSQL major version. Use 16 for best pgvector support."
}

variable "postgres_storage_mb" {
  type        = number
  default     = 32768
  description = "PostgreSQL storage size in MB (32 GB minimum)."
}

variable "postgres_backup_retention_days" {
  type        = number
  default     = 7
  description = "PostgreSQL backup retention days (7-35)."
}

# ============================================================================
# RAG Configuration
# ============================================================================

variable "embedding_dimension" {
  type        = number
  default     = 1536
  description = <<-EOT
    Dimension of embedding vectors.
    
    Common values:
    - 1536: OpenAI text-embedding-ada-002, Cohere embed-english-v3.0
    - 768: OpenAI text-embedding-3-small
    - 384: all-MiniLM-L6-v2
    
    This value is used across all components and must match your embedding model.
  EOT
}

variable "embedding_provider" {
  type        = string
  default     = "cohere"
  description = <<-EOT
    Embedding provider to use.
    
    Options: "cohere", "openai", "azure-openai"
    
    This is informational for documentation purposes.
  EOT
}

variable "vector_index_type" {
  type        = string
  default     = "ivfflat"
  description = <<-EOT
    pgvector index type.
    
    Options:
    - "ivfflat": Inverted file flat (default, good for most use cases)
    - "hnsw": Hierarchical Navigable Small World (better recall, PostgreSQL 15+)
  EOT

  validation {
    condition     = contains(["ivfflat", "hnsw"], var.vector_index_type)
    error_message = "Vector index type must be 'ivfflat' or 'hnsw'."
  }
}

variable "vector_index_params" {
  type        = map(number)
  default     = { lists = 100 }
  description = <<-EOT
    Parameters for vector index.
    
    IVFFlat:
    - lists: Number of clusters (default: 100, tune to sqrt(n_rows))
    
    HNSW:
    - m: Max connections per node (default: 16)
    - ef_construction: Size of dynamic candidate list (default: 64)
  EOT
}

# ============================================================================
# Hybrid Search Configuration
# ============================================================================

variable "hybrid_alpha" {
  type        = number
  default     = 0.5
  description = <<-EOT
    Weight for hybrid search fusion (0.0 to 1.0).
    
    hybrid_score = alpha * vector_score + (1 - alpha) * bm25_score
    
    - 0.0: Pure BM25 (keyword search)
    - 0.5: Equal weight (default)
    - 1.0: Pure vector (semantic search)
  EOT

  validation {
    condition     = var.hybrid_alpha >= 0.0 && var.hybrid_alpha <= 1.0
    error_message = "Hybrid alpha must be between 0.0 and 1.0."
  }
}

variable "fusion_strategy" {
  type        = string
  default     = "weighted_sum"
  description = <<-EOT
    Strategy for combining vector and BM25 scores.
    
    Options:
    - "weighted_sum": Linear combination with hybrid_alpha
    - "rrf": Reciprocal Rank Fusion
  EOT

  validation {
    condition     = contains(["weighted_sum", "rrf"], var.fusion_strategy)
    error_message = "Fusion strategy must be 'weighted_sum' or 'rrf'."
  }
}

# ============================================================================
# Reranker Configuration
# ============================================================================

variable "reranker_model" {
  type        = string
  default     = "cohere"
  description = <<-EOT
    Default reranker model to use.
    
    Options:
    - "cohere": Cohere Rerank v3.5 (high quality)
    - "bge": BGE reranker (open source, cost-effective)
  EOT

  validation {
    condition     = contains(["cohere", "bge"], var.reranker_model)
    error_message = "Reranker model must be 'cohere' or 'bge'."
  }
}

# ============================================================================
# Secrets (Sensitive - Provide via Environment Variables)
# ============================================================================
# These variables should be provided via TF_VAR_* environment variables
# or via secure secret management. Never commit actual values to git.

variable "supabase_jwt_secret" {
  type        = string
  sensitive   = true
  default     = null
  description = "Supabase JWT secret (generate with: openssl rand -base64 32)."
}

variable "supabase_anon_key" {
  type        = string
  sensitive   = true
  default     = null
  description = "Supabase anonymous key (generate via Supabase tooling)."
}

variable "supabase_service_role_key" {
  type        = string
  sensitive   = true
  default     = null
  description = "Supabase service role key (generate via Supabase tooling)."
}

variable "cohere_api_key" {
  type        = string
  sensitive   = true
  default     = null
  description = "Cohere API key for embeddings and reranking."
}

variable "openai_api_key" {
  type        = string
  sensitive   = true
  default     = null
  description = "OpenAI API key (if using OpenAI embeddings)."
}

variable "laminar_api_key" {
  type        = string
  sensitive   = true
  default     = null
  description = "Laminar Cloud API key for observability."
}

# ============================================================================
# SharePoint Configuration (for Ingestion Function)
# ============================================================================

variable "sharepoint_tenant_id" {
  type        = string
  default     = null
  description = "SharePoint tenant ID for document ingestion."
}

variable "sharepoint_site_id" {
  type        = string
  default     = null
  description = "SharePoint site ID containing source documents."
}

variable "sharepoint_library_id" {
  type        = string
  default     = null
  description = "SharePoint library ID containing source documents."
}

variable "sharepoint_folder_path" {
  type        = string
  default     = null
  description = "SharePoint folder path containing source documents."
}

# ============================================================================
# Entra ID Configuration (for Static Web App Auth)
# ============================================================================

variable "entra_tenant_id" {
  type        = string
  default     = null
  description = "Entra ID (Azure AD) tenant ID for authentication."
}

variable "entra_client_id" {
  type        = string
  default     = null
  description = "Entra ID application (client) ID for Static Web App."
}
