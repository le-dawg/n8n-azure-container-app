# Database Migrations

This directory contains SQL migration files for the RAG (Retrieval-Augmented Generation) database schema.

## Overview

The database schema supports:
- **Document source tracking** with idempotent ingestion (hash-based deduplication)
- **Logical document modeling** with metadata and classification
- **Text chunking** with pgvector embeddings for semantic search
- **Full-text search** (FTS) with trigram indexes for BM25 hybrid retrieval
- **Multi-tenancy** via Row-Level Security (RLS) scaffolding
- **Audit trails** with timestamps and metadata

## Prerequisites

### Required PostgreSQL Extensions

The following extensions must be enabled before running migrations:

1. **vector** - Vector similarity search (pgvector)
2. **pg_trgm** - Trigram-based text similarity
3. **unaccent** - Remove diacritics for better text search
4. **pg_stat_statements** - Query performance monitoring

These are automatically enabled in the migration files, but ensure your PostgreSQL server allows them. In Azure PostgreSQL Flexible Server, configure:

```hcl
configurations = {
  "azure.extensions" = {
    value = "VECTOR,PG_TRGM,UNACCENT,PG_STAT_STATEMENTS"
  }
}
```

## Migration Files

### 0001_base.sql

**Purpose**: Create foundational schema for RAG workload

**Creates**:
- Tables: `sources`, `documents`, `chunks`
- Roles: `app_admin`, `app_user`
- Indexes: B-tree, GIN (full-text), trigram
- Triggers: Automatic tsvector updates for FTS
- RLS: Enabled but not enforced (policies commented out)

**Dependencies**: None (base migration)

## Running Migrations

### Method 1: psql (Recommended)

```bash
# Get connection string from Terraform
CONNECTION_STRING=$(terraform output -raw postgres_connection_string)

# Run migration
psql "$CONNECTION_STRING" -f db/0001_base.sql

# Verify extensions
psql "$CONNECTION_STRING" -c "SELECT extname, extversion FROM pg_extension;"

# Verify tables
psql "$CONNECTION_STRING" -c "\dt"
```

### Method 2: pgAdmin or Azure Portal Query Editor

1. Connect to your PostgreSQL server
2. Open `db/0001_base.sql`
3. Execute the entire script
4. Verify success messages in output

### Method 3: Terraform Provisioner (Dev Only)

For development environments, you can use a Terraform provisioner:

```hcl
resource "null_resource" "run_migrations" {
  depends_on = [module.postgres]

  provisioner "local-exec" {
    command = "psql '${module.postgres.connection_string}' -f db/0001_base.sql"
  }

  # Re-run if migration file changes
  triggers = {
    migration_file = filesha256("db/0001_base.sql")
  }
}
```

**Note**: This approach is acceptable for dev environments but NOT recommended for production. Use a proper migration tool (see below) for production.

## Post-Migration Tasks

### 1. Create Vector Index

Vector indexes require training data. Create them AFTER ingesting at least 1000 chunks:

```sql
-- IVFFlat (default choice)
CREATE INDEX idx_chunks_embedding_ivfflat 
ON chunks USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);  -- Tune based on dataset size: sqrt(n_rows)

-- Or HNSW (PostgreSQL 15+, better recall)
CREATE INDEX idx_chunks_embedding_hnsw
ON chunks USING hnsw (embedding vector_cosine_ops)
WITH (m = 16, ef_construction = 64);
```

**Guidelines**:
- **IVFFlat lists**: Start with `sqrt(n_rows)`, e.g., 100 for 10K chunks
- **HNSW m**: 16 (default), increase for better recall (more memory)
- **HNSW ef_construction**: 64 (default), increase for better index quality

### 2. Enable RLS Policies (Production)

Uncomment and customize RLS policies in `0001_base.sql`:

```sql
-- Example: Tenant isolation
CREATE POLICY tenant_isolation ON chunks
  FOR ALL TO app_user
  USING (tenant_id::TEXT = current_setting('app.tenant_id', true));
```

Set tenant context in your application:

```python
# Python example
cursor.execute("SET LOCAL app.tenant_id = %s", (user_tenant_id,))
# Run queries...
```

### 3. Verify Full-Text Search

Test that tsvector triggers are working:

```sql
-- Insert test document
INSERT INTO documents (tenant_id, title, full_text)
VALUES (gen_random_uuid(), 'Test Document', 'This is a test document for full-text search');

-- Verify search_vector was populated
SELECT title, search_vector FROM documents WHERE title = 'Test Document';

-- Test full-text search
SELECT title 
FROM documents 
WHERE search_vector @@ to_tsquery('english', 'test & document');
```

## Schema Overview

### Tables

#### sources
Tracks raw source files (PDFs, DOCX, etc.)

**Key columns**:
- `hash`: SHA256 hash for idempotent ingestion
- `tenant_id`: Multi-tenancy support
- `ingestion_status`: Track processing state

#### documents
Logical documents extracted from sources

**Key columns**:
- `source_id`: Link to source file
- `title`, `full_text`: Document content
- `classification`: Security level (public, internal, confidential)
- `effective_date`, `expiration_date`: Compliance tracking
- `search_vector`: Auto-updated for full-text search

#### chunks
Text chunks with vector embeddings for RAG

**Key columns**:
- `document_id`: Link to parent document
- `content`: Chunk text (512-1024 tokens)
- `embedding`: Vector embedding (VECTOR(1536))
- `chunk_index`: Position within document
- `search_vector`: Auto-updated for BM25

### Indexes

#### B-tree Indexes
- Foreign keys (document_id, source_id)
- Tenant IDs
- Timestamps (for sorting)
- Status fields

#### GIN Indexes
- `search_vector`: Full-text search (tsvector)
- `content`: Trigram similarity (pg_trgm)
- `metadata`: JSONB queries

#### Vector Indexes (Created Post-Migration)
- `embedding`: IVFFlat or HNSW for ANN search

## Query Examples

### Semantic Search (Vector)

```sql
-- Find similar chunks
SELECT id, content, embedding <=> $1::vector AS distance
FROM chunks
WHERE tenant_id = $2
ORDER BY distance
LIMIT 10;
```

### Full-Text Search (BM25)

```sql
-- BM25 ranking
SELECT 
  id, 
  content, 
  ts_rank(search_vector, query) AS rank
FROM chunks, plainto_tsquery('english', $1) query
WHERE search_vector @@ query
  AND tenant_id = $2
ORDER BY rank DESC
LIMIT 10;
```

### Hybrid Search (Vector + BM25)

```sql
WITH vector_results AS (
  SELECT id, content, 1 - (embedding <=> $1::vector) AS vector_score
  FROM chunks
  WHERE tenant_id = $3
  ORDER BY embedding <=> $1::vector
  LIMIT 100
),
bm25_results AS (
  SELECT id, content, ts_rank(search_vector, query) AS bm25_score
  FROM chunks, plainto_tsquery('english', $2) query
  WHERE search_vector @@ query AND tenant_id = $3
  ORDER BY bm25_score DESC
  LIMIT 100
)
SELECT 
  COALESCE(v.id, b.id) AS id,
  COALESCE(v.content, b.content) AS content,
  -- Weighted hybrid score (alpha=0.5)
  COALESCE(v.vector_score, 0) * 0.5 + 
  COALESCE(b.bm25_score, 0) * 0.5 AS hybrid_score
FROM vector_results v
FULL OUTER JOIN bm25_results b ON v.id = b.id
ORDER BY hybrid_score DESC
LIMIT 10;
```

## Performance Tuning

### Analyze Tables

After ingestion, update statistics for query planner:

```sql
ANALYZE sources;
ANALYZE documents;
ANALYZE chunks;
```

### Monitor Query Performance

```sql
-- Top 10 slowest queries
SELECT 
  query,
  calls,
  total_exec_time,
  mean_exec_time,
  max_exec_time
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

-- Reset statistics
SELECT pg_stat_statements_reset();
```

### Index Usage

```sql
-- Check index usage
SELECT 
  schemaname,
  tablename,
  indexname,
  idx_scan AS scans,
  idx_tup_read AS tuples_read,
  idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- Check index size
SELECT 
  tablename,
  indexname,
  pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC;
```

## Backup and Restore

### Backup Schema and Data

```bash
# Full database backup
pg_dump "$CONNECTION_STRING" -Fc -f backup.dump

# Schema only
pg_dump "$CONNECTION_STRING" -s -f schema.sql

# Data only (for specific table)
pg_dump "$CONNECTION_STRING" -a -t chunks -f chunks_data.sql
```

### Restore

```bash
# Restore full backup
pg_restore -d "$CONNECTION_STRING" backup.dump

# Restore schema
psql "$CONNECTION_STRING" -f schema.sql
```

## Migration Strategy for Production

For production deployments, use a proper migration tool instead of manual psql:

### Option 1: Flyway

```bash
# Install Flyway
brew install flyway  # macOS
# or download from https://flywaydb.org/

# Configure connection
export FLYWAY_URL="jdbc:postgresql://HOST:5432/DATABASE"
export FLYWAY_USER="admin"
export FLYWAY_PASSWORD="password"

# Run migrations
flyway migrate
```

### Option 2: Liquibase

```bash
# Install Liquibase
brew install liquibase  # macOS

# Create changelog.xml referencing SQL files
# Run migrations
liquibase update
```

### Option 3: Alembic (Python)

```python
# For Python-based projects
pip install alembic psycopg2-binary

# Initialize
alembic init migrations

# Configure alembic.ini and env.py
# Create migration
alembic revision -m "Create base schema"

# Run migrations
alembic upgrade head
```

### Option 4: Azure Database Migration Service

For enterprise scenarios, consider Azure Database Migration Service for minimal downtime migrations.

## Troubleshooting

### Issue: Extension not available

```sql
-- Check available extensions
SELECT name FROM pg_available_extensions WHERE name IN ('vector', 'pg_trgm', 'unaccent');

-- If missing, ensure azure.extensions is configured in Terraform
```

### Issue: Cannot create vector index

**Symptom**: Error about insufficient training data

**Solution**: Insert at least 1000 rows before creating IVFFlat index, or use a smaller `lists` parameter:

```sql
-- Use smaller lists for small datasets
CREATE INDEX idx_chunks_embedding_ivfflat 
ON chunks USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 10);  -- Min: 10, but affects performance

-- Rebuild later with optimal value
DROP INDEX idx_chunks_embedding_ivfflat;
CREATE INDEX idx_chunks_embedding_ivfflat 
ON chunks USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);
```

### Issue: RLS blocking queries

If RLS is enabled but policies aren't working:

```sql
-- Temporarily disable RLS (dev only!)
ALTER TABLE chunks DISABLE ROW LEVEL SECURITY;

-- Or use app_admin role which bypasses RLS
SET ROLE app_admin;
-- Run queries...
RESET ROLE;
```

### Issue: Slow full-text search

Ensure GIN indexes are created:

```sql
-- Check if index exists
SELECT indexname FROM pg_indexes WHERE tablename = 'chunks' AND indexname LIKE '%search_vector%';

-- Recreate if needed
DROP INDEX IF EXISTS idx_chunks_search_vector;
CREATE INDEX idx_chunks_search_vector ON chunks USING gin(search_vector);

-- Update statistics
ANALYZE chunks;
```

## Contributing

When adding new migrations:

1. **Naming**: Use format `XXXX_description.sql` (e.g., `0002_add_tags.sql`)
2. **Idempotency**: Use `IF NOT EXISTS`, `DROP IF EXISTS`, etc.
3. **Rollback**: Create corresponding `XXXX_description_down.sql` if possible
4. **Testing**: Test on dev database before production
5. **Documentation**: Update this README with migration details

## Resources

- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [PostgreSQL Full-Text Search](https://www.postgresql.org/docs/current/textsearch.html)
- [Row-Level Security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- [pg_trgm](https://www.postgresql.org/docs/current/pgtrgm.html)

---

**Last Updated**: 2025-11-24  
**Version**: 1.0.0
