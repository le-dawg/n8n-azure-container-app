# Azure PostgreSQL Flexible Server with pgvector

This Terraform module provisions an Azure Database for PostgreSQL Flexible Server optimized for RAG (Retrieval-Augmented Generation) workloads with pgvector support for vector embeddings and full-text search capabilities.

## Features

- 🎯 **pgvector Extension**: Native vector storage and similarity search
- 🔍 **Full-Text Search**: pg_trgm and unaccent for BM25 hybrid search
- 📊 **Performance Tuning**: Configurable memory settings for vector operations
- 🔒 **Security**: Firewall rules, public/private network options
- 💾 **Backup & HA**: Configurable retention, geo-redundancy, zone-redundant HA
- 📈 **Scalable**: From burstable SKUs (dev) to memory-optimized (prod)

## Usage

### Basic Configuration (Development)

```hcl
module "postgres" {
  source = "./modules/postgres_flexible"

  name                = "myapp-postgres-dev"
  resource_group_name = "my-rg"
  location            = "northeurope"

  administrator_login    = "psqladmin"
  administrator_password = random_password.postgres.result

  postgres_version = 16
  sku_name         = "B_Standard_B1ms"  # Burstable, cost-optimized
  storage_mb       = 32768                # 32 GB

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

  firewall_rules = {
    azure_services = {
      name             = "AllowAzureServices"
      start_ip_address = "0.0.0.0"
      end_ip_address   = "0.0.0.0"
    }
  }

  tags = {
    environment = "dev"
    workload    = "rag"
  }
}
```

### Production Configuration with HA

```hcl
module "postgres_prod" {
  source = "./modules/postgres_flexible"

  name                = "myapp-postgres-prod"
  resource_group_name = "my-rg-prod"
  location            = "northeurope"

  administrator_login    = "psqladmin"
  administrator_password = data.azurerm_key_vault_secret.postgres_password.value

  postgres_version = 16
  sku_name         = "GP_Standard_D2s_v3"  # General Purpose, 2 vCore
  storage_mb       = 65536                   # 64 GB

  # High Availability
  enable_high_availability  = true
  availability_zone         = 1
  standby_availability_zone = 2

  # Backup Configuration
  backup_retention_days        = 14
  geo_redundant_backup_enabled = true

  # Performance Tuning for Vector Search
  shared_buffers_mb       = 1024  # 1 GB
  work_mem_mb             = 64
  maintenance_work_mem_mb = 512
  max_connections         = 200

  databases = {
    rag = {
      name      = "rag"
      charset   = "UTF8"
      collation = "en_US.utf8"
    }
  }

  firewall_rules = {
    azure_services = {
      name             = "AllowAzureServices"
      start_ip_address = "0.0.0.0"
      end_ip_address   = "0.0.0.0"
    }
  }

  tags = {
    environment = "prod"
    workload    = "rag"
  }
}
```

### RAG-Optimized Configuration

```hcl
module "postgres_rag" {
  source = "./modules/postgres_flexible"

  name                = "rag-postgres"
  resource_group_name = "my-rg"
  location            = "northeurope"

  administrator_login    = "psqladmin"
  administrator_password = var.postgres_password

  postgres_version = 16
  sku_name         = "GP_Standard_D2s_v3"
  storage_mb       = 65536

  # Optimize for vector operations
  shared_buffers_mb       = 1024  # Large buffer for vector index caching
  work_mem_mb             = 128   # Higher for vector similarity computations
  maintenance_work_mem_mb = 1024  # Fast vector index building

  primary_database = "rag"

  databases = {
    rag = {
      name      = "rag"
      charset   = "UTF8"
      collation = "en_US.utf8"
    }
  }

  firewall_rules = {
    azure_services = {
      name             = "AllowAzureServices"
      start_ip_address = "0.0.0.0"
      end_ip_address   = "0.0.0.0"
    }
    admin_ip = {
      name             = "AdminAccess"
      start_ip_address = "203.0.113.10"
      end_ip_address   = "203.0.113.10"
    }
  }

  tags = {
    environment = "dev"
    workload    = "rag"
  }
}

# After applying, enable extensions:
resource "null_resource" "enable_extensions" {
  depends_on = [module.postgres_rag]

  provisioner "local-exec" {
    command = <<-EOT
      psql "${module.postgres_rag.connection_string}" << 'EOF'
      ${module.postgres_rag.extension_setup_sql}
      EOF
    EOT
  }
}
```

## Post-Deployment Setup

After deploying the PostgreSQL server, you need to enable extensions:

```bash
# Get connection string
CONNECTION_STRING=$(terraform output -raw postgres_connection_string)

# Connect and enable extensions
psql "$CONNECTION_STRING" << 'EOF'
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Verify
SELECT extname, extversion FROM pg_extension;
EOF
```

Or use the provided SQL output:

```bash
terraform output -raw extension_setup_sql | psql "$CONNECTION_STRING"
```

## pgvector Usage

Once pgvector is enabled, you can create tables with vector columns:

```sql
-- Create table with 1536-dimensional vectors (OpenAI/Cohere embedding size)
CREATE TABLE chunks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content TEXT NOT NULL,
    embedding VECTOR(1536),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create IVFFlat index for fast similarity search
-- Note: Requires enough data rows for training (>= lists parameter)
CREATE INDEX ON chunks USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- Alternative: HNSW index (may require PostgreSQL 15+)
-- CREATE INDEX ON chunks USING hnsw (embedding vector_cosine_ops)
-- WITH (m = 16, ef_construction = 64);

-- Similarity search query
SELECT id, content, embedding <=> '[0.1, 0.2, ...]'::vector AS distance
FROM chunks
ORDER BY distance
LIMIT 10;
```

## BM25 / Full-Text Search Setup

The module enables `pg_trgm` for trigram-based text search:

```sql
-- Create GIN index for full-text search
CREATE INDEX ON chunks USING gin (to_tsvector('english', content));

-- Or use pg_trgm for fuzzy matching
CREATE INDEX ON chunks USING gin (content gin_trgm_ops);

-- Full-text search query
SELECT id, content, ts_rank(to_tsvector('english', content), query) AS rank
FROM chunks, plainto_tsquery('english', 'search terms') query
WHERE to_tsvector('english', content) @@ query
ORDER BY rank DESC
LIMIT 10;

-- Trigram similarity search
SELECT id, content, similarity(content, 'search terms') AS sim
FROM chunks
WHERE content % 'search terms'  -- % operator for trigram matching
ORDER BY sim DESC
LIMIT 10;
```

## Hybrid Search (Vector + BM25)

Combine vector similarity with text relevance:

```sql
WITH vector_results AS (
  SELECT id, content, embedding <=> $1::vector AS vector_distance
  FROM chunks
  ORDER BY vector_distance
  LIMIT 100
),
bm25_results AS (
  SELECT id, content, ts_rank(to_tsvector('english', content), query) AS bm25_score
  FROM chunks, plainto_tsquery('english', $2) query
  WHERE to_tsvector('english', content) @@ query
  ORDER BY bm25_score DESC
  LIMIT 100
)
SELECT 
  COALESCE(v.id, b.id) AS id,
  COALESCE(v.content, b.content) AS content,
  -- Normalized hybrid score (adjust alpha for weighting)
  (1 - COALESCE(v.vector_distance, 1)) * 0.5 + COALESCE(b.bm25_score, 0) * 0.5 AS hybrid_score
FROM vector_results v
FULL OUTER JOIN bm25_results b ON v.id = b.id
ORDER BY hybrid_score DESC
LIMIT 10;
```

## SKU Recommendations

### Development / Testing
```hcl
sku_name   = "B_Standard_B1ms"  # 1 vCore, 2 GB RAM, ~$15/month
storage_mb = 32768               # 32 GB
```

### Small Production (≤10 RPS)
```hcl
sku_name   = "GP_Standard_D2s_v3"  # 2 vCore, 8 GB RAM, ~$100/month
storage_mb = 65536                  # 64 GB
enable_high_availability = true
```

### Medium Production (≤100 RPS)
```hcl
sku_name   = "GP_Standard_D4s_v3"  # 4 vCore, 16 GB RAM, ~$200/month
storage_mb = 131072                 # 128 GB
enable_high_availability = true
```

### High Performance RAG
```hcl
sku_name   = "MO_Standard_E4s_v3"  # 4 vCore, 32 GB RAM (memory-optimized)
storage_mb = 262144                 # 256 GB
shared_buffers_mb = 4096
work_mem_mb = 256
```

## Performance Tuning Guidelines

### Memory Settings

For pgvector performance, tune these parameters:

| Parameter | Development | Small Prod | Large Prod |
|-----------|-------------|------------|------------|
| shared_buffers | 256 MB | 1 GB | 4 GB |
| work_mem | 16 MB | 64 MB | 128 MB |
| maintenance_work_mem | 256 MB | 512 MB | 2 GB |

**Rule of thumb**:
- `shared_buffers`: 25% of RAM
- `work_mem`: Balance between query performance and max_connections
- `maintenance_work_mem`: Larger = faster index builds

### Connection Settings

```hcl
max_connections = 200  # Adjust based on: ACA containers + Functions + admin
```

**Formula**: `work_mem * max_connections < available_RAM`

Example:
- 8 GB RAM server
- Reserve 2 GB for OS and Postgres
- 6 GB available for connections
- With work_mem = 64 MB: max_connections ≤ 96

## Security Best Practices

### 1. Use Private Endpoints (Production)

```hcl
public_network_access_enabled = false
# Configure delegated subnet and private endpoint (future enhancement)
```

### 2. Restrict Firewall Rules

```hcl
firewall_rules = {
  # Only allow specific Azure services
  aca_environment = {
    name             = "ACAEnvironment"
    start_ip_address = "10.0.1.0"
    end_ip_address   = "10.0.1.255"
  }
  # Admin access from specific IP
  admin = {
    name             = "AdminAccess"
    start_ip_address = "203.0.113.10"
    end_ip_address   = "203.0.113.10"
  }
}
```

### 3. Use Managed Identity

Enable managed identity on Container Apps and Functions, then configure PostgreSQL to accept Azure AD authentication (future enhancement).

### 4. Password Management

```hcl
# Generate random password
resource "random_password" "postgres" {
  length  = 32
  special = true
}

# Store in Key Vault
resource "azurerm_key_vault_secret" "postgres_password" {
  name         = "postgres-password"
  value        = random_password.postgres.result
  key_vault_id = azurerm_key_vault.this.id
}

# Reference in module
administrator_password = random_password.postgres.result
```

## Monitoring

### Query Performance

```sql
-- View slow queries
SELECT * FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

-- Vector index usage
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE indexname LIKE '%embedding%';
```

### Connection Monitoring

```sql
-- Current connections
SELECT count(*) FROM pg_stat_activity;

-- Connections by database
SELECT datname, count(*)
FROM pg_stat_activity
GROUP BY datname;
```

## Troubleshooting

### Issue: pgvector extension not available

**Solution**: Ensure `azure.extensions` includes VECTOR:
```hcl
configurations = {
  "azure.extensions" = {
    value = "VECTOR,PG_TRGM,UNACCENT"
  }
}
```

Then restart the server if needed (check Azure Portal).

### Issue: Index creation is slow

**Solution**: Increase `maintenance_work_mem`:
```hcl
maintenance_work_mem_mb = 1024  # 1 GB
```

### Issue: Out of memory errors

**Solution**: Reduce connections or work_mem:
```hcl
max_connections = 100
work_mem_mb     = 32
```

### Issue: Cannot connect from Container App

**Solution**: Add firewall rule for Azure services:
```hcl
firewall_rules = {
  azure_services = {
    name             = "AllowAzureServices"
    start_ip_address = "0.0.0.0"
    end_ip_address   = "0.0.0.0"
  }
}
```

## Cost Optimization Tips

1. **Use Burstable SKUs for dev**: B_Standard_B1ms instead of GP_Standard_D2s_v3 (10x cheaper)
2. **Disable HA for dev**: Save 2x server cost
3. **Right-size storage**: Start small, auto-grows as needed
4. **Disable geo-redundant backup for dev**: No cross-region replication cost
5. **Use reserved capacity for prod**: 1-year or 3-year commitment saves 30-65%

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.8, < 2.0 |
| azurerm | ~> 4.5 |
| random | ~> 3.7 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.5 |
| random | ~> 3.7 |

## Inputs

See [variables.tf](./variables.tf) for complete input documentation.

## Outputs

See [outputs.tf](./outputs.tf) for complete output documentation.

## Related Resources

- [Azure PostgreSQL Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/)
- [pgvector Extension](https://github.com/pgvector/pgvector)
- [PostgreSQL Full-Text Search](https://www.postgresql.org/docs/current/textsearch.html)
- [Azure PostgreSQL Extensions](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-extensions)

## License

This module is part of the n8n-azure-container-app repository.
