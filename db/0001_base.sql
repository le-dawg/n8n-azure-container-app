-- ============================================================================
-- RAG Database Schema - Base Migration (0001)
-- ============================================================================
--
-- This migration creates the foundational schema for a Retrieval-Augmented
-- Generation (RAG) system with support for:
-- - Document source tracking with idempotency (hashing)
-- - Logical document modeling with metadata
-- - Text chunks with pgvector embeddings for semantic search
-- - Full-text search indexes for BM25 hybrid retrieval
-- - Row-Level Security (RLS) scaffolding for multi-tenancy
--
-- Prerequisites:
-- - PostgreSQL 11+ (recommended: 16)
-- - Extensions: vector, pg_trgm, unaccent, pg_stat_statements
--
-- Usage:
--   psql "<CONNECTION_STRING>" -f db/0001_base.sql
--
-- ============================================================================

-- ============================================================================
-- Enable Required Extensions
-- ============================================================================
-- These must be enabled before creating tables that use them

-- pgvector: Vector similarity search for embeddings
CREATE EXTENSION IF NOT EXISTS vector;

-- pg_trgm: Trigram-based text similarity and GIN indexes for LIKE/ILIKE
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- unaccent: Remove diacritics for better text search across languages
CREATE EXTENSION IF NOT EXISTS unaccent;

-- pg_stat_statements: Query performance monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

\echo 'Extensions enabled successfully'
\echo ''

-- ============================================================================
-- Create Roles for Row-Level Security (RLS)
-- ============================================================================
-- These roles provide a foundation for multi-tenant access control
-- Default: RLS is enabled but no policies are enforced (allowing setup/testing)
-- Production: Uncomment and customize policies below

-- app_admin: Bypasses RLS, used by internal services and migrations
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_admin') THEN
    CREATE ROLE app_admin NOLOGIN;
    \echo 'Created role: app_admin'
  END IF;
END $$;

-- app_user: Subject to RLS policies, used by end-user-facing services
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
    CREATE ROLE app_user NOLOGIN;
    \echo 'Created role: app_user'
  END IF;
END $$;

-- Grant necessary privileges
GRANT CONNECT ON DATABASE current_database() TO app_admin, app_user;
GRANT USAGE ON SCHEMA public TO app_admin, app_user;

\echo ''
\echo 'Roles created successfully'
\echo ''

-- ============================================================================
-- Table: sources
-- ============================================================================
-- Tracks raw source files (PDFs, DOCX, etc.) from SharePoint or other origins
-- hash column enables idempotent ingestion (skip if already processed)

CREATE TABLE IF NOT EXISTS sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Source location and identification
    path TEXT NOT NULL,              -- Full path in source system (e.g., SharePoint URL)
    file_name TEXT NOT NULL,         -- Original filename
    doc_type TEXT,                   -- e.g., 'pdf', 'docx', 'txt'
    mime_type TEXT,                  -- MIME type of the file
    
    -- Idempotency and versioning
    hash TEXT NOT NULL UNIQUE,       -- SHA256 hash of file content for deduplication
    file_size_bytes BIGINT,          -- Original file size
    version TEXT,                    -- Document version if available
    
    -- Multi-tenancy
    tenant_id UUID NOT NULL,         -- Tenant or organization identifier
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    ingested_at TIMESTAMPTZ,         -- When ingestion completed
    ingestion_status TEXT,           -- 'pending', 'processing', 'completed', 'failed'
    ingestion_error TEXT,            -- Error message if ingestion failed
    
    -- Additional metadata (JSON for flexibility)
    metadata JSONB DEFAULT '{}'::JSONB
);

-- Indexes for sources
CREATE INDEX IF NOT EXISTS idx_sources_tenant_id ON sources(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sources_hash ON sources(hash);
CREATE INDEX IF NOT EXISTS idx_sources_created_at ON sources(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sources_ingestion_status ON sources(ingestion_status) WHERE ingestion_status IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sources_metadata ON sources USING gin(metadata);

\echo 'Table created: sources'

-- ============================================================================
-- Table: documents
-- ============================================================================
-- Represents logical documents extracted from sources
-- A single source may yield multiple documents (e.g., sections of a large PDF)

CREATE TABLE IF NOT EXISTS documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Relationship to source
    source_id UUID NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    
    -- Document content and metadata
    title TEXT,                       -- Document title or heading
    full_text TEXT,                   -- Full document text (for FTS if not using chunks)
    excerpt TEXT,                     -- Short summary or first paragraph
    
    -- Classification and compliance
    classification TEXT,              -- e.g., 'public', 'internal', 'confidential'
    document_type TEXT,               -- e.g., 'policy', 'procedure', 'guideline'
    effective_date DATE,              -- When document becomes effective
    expiration_date DATE,             -- When document expires or should be reviewed
    version TEXT,                     -- Document version number
    status TEXT,                      -- e.g., 'draft', 'active', 'archived', 'superseded'
    
    -- Multi-tenancy
    tenant_id UUID NOT NULL,
    
    -- Author and ownership
    author TEXT,
    department TEXT,
    owner_email TEXT,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    published_at TIMESTAMPTZ,         -- Original publication date
    
    -- Additional metadata (JSON for flexibility)
    metadata JSONB DEFAULT '{}'::JSONB,
    
    -- Full-text search column (automatically updated by trigger)
    search_vector TSVECTOR
);

-- Indexes for documents
CREATE INDEX IF NOT EXISTS idx_documents_source_id ON documents(source_id);
CREATE INDEX IF NOT EXISTS idx_documents_tenant_id ON documents(tenant_id);
CREATE INDEX IF NOT EXISTS idx_documents_created_at ON documents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_documents_effective_date ON documents(effective_date DESC);
CREATE INDEX IF NOT EXISTS idx_documents_classification ON documents(classification);
CREATE INDEX IF NOT EXISTS idx_documents_document_type ON documents(document_type);
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status);
CREATE INDEX IF NOT EXISTS idx_documents_metadata ON documents USING gin(metadata);

-- Full-text search index (GIN for tsvector)
CREATE INDEX IF NOT EXISTS idx_documents_search_vector ON documents USING gin(search_vector);

-- Trigram indexes for fuzzy matching on title and excerpt
CREATE INDEX IF NOT EXISTS idx_documents_title_trgm ON documents USING gin(title gin_trgm_ops);

\echo 'Table created: documents'

-- ============================================================================
-- Table: chunks
-- ============================================================================
-- Text chunks with vector embeddings for semantic search
-- This is the primary table for RAG retrieval

CREATE TABLE IF NOT EXISTS chunks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Relationship to document
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    
    -- Chunk positioning
    chunk_index INTEGER NOT NULL,     -- 0-based index within document
    page_number INTEGER,              -- Source page number (if applicable)
    section_heading TEXT,             -- Heading of the section this chunk belongs to
    
    -- Chunk content
    content TEXT NOT NULL,            -- The actual text chunk (typically 512-1024 tokens)
    token_count INTEGER,              -- Number of tokens (for LLM context management)
    
    -- Vector embedding for semantic search
    -- Dimension is configurable (1536 for OpenAI/Cohere, 384 for MiniLM, etc.)
    -- This will be created dynamically based on embedding_dimension variable
    -- For now, using 1536 as default (can be altered later if needed)
    embedding VECTOR(1536),
    
    -- Multi-tenancy
    tenant_id UUID NOT NULL,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Additional metadata (JSON for flexibility)
    metadata JSONB DEFAULT '{}'::JSONB,
    
    -- Full-text search column
    search_vector TSVECTOR,
    
    -- Ensure chunks are ordered within a document
    UNIQUE(document_id, chunk_index)
);

-- Indexes for chunks
CREATE INDEX IF NOT EXISTS idx_chunks_document_id ON chunks(document_id);
CREATE INDEX IF NOT EXISTS idx_chunks_tenant_id ON chunks(tenant_id);
CREATE INDEX IF NOT EXISTS idx_chunks_created_at ON chunks(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chunks_metadata ON chunks USING gin(metadata);

-- Full-text search index (GIN for tsvector)
CREATE INDEX IF NOT EXISTS idx_chunks_search_vector ON chunks USING gin(search_vector);

-- Trigram index for fuzzy matching on content
CREATE INDEX IF NOT EXISTS idx_chunks_content_trgm ON chunks USING gin(content gin_trgm_ops);

\echo 'Table created: chunks'
\echo ''

-- ============================================================================
-- Vector Index on chunks.embedding
-- ============================================================================
-- This index enables fast approximate nearest neighbor (ANN) search
-- 
-- Options:
-- 1. IVFFlat: Faster to build, good for most use cases
-- 2. HNSW: Better recall, slower to build, requires PostgreSQL 15+
--
-- For production, tune these parameters based on your dataset size:
-- - IVFFlat lists: sqrt(total_rows) is a good starting point
-- - HNSW m: 16 (default), higher = better recall but more memory
-- - HNSW ef_construction: 64 (default), higher = better quality but slower build
--
-- NOTE: IVFFlat requires training data. Build this index AFTER inserting
-- sufficient rows (>= lists parameter, ideally 10x). For initial setup,
-- you can create the index with fewer rows and rebuild later.

-- IVFFlat index (default choice)
-- Uncomment after ingesting at least 1000 chunks for proper training
-- CREATE INDEX IF NOT EXISTS idx_chunks_embedding_ivfflat 
-- ON chunks USING ivfflat (embedding vector_cosine_ops)
-- WITH (lists = 100);  -- Adjust based on data size: sqrt(n_rows)

-- HNSW index (alternative, better recall, requires PG 15+)
-- Uncomment if using PostgreSQL 15+ and prefer HNSW
-- CREATE INDEX IF NOT EXISTS idx_chunks_embedding_hnsw
-- ON chunks USING hnsw (embedding vector_cosine_ops)
-- WITH (m = 16, ef_construction = 64);

\echo 'Note: Vector indexes on chunks.embedding are commented out'
\echo 'Create them manually after ingesting sufficient data for training'
\echo ''

-- ============================================================================
-- Triggers for Automatic tsvector Updates
-- ============================================================================
-- These triggers maintain the search_vector columns for full-text search

-- Function to update search_vector for documents
CREATE OR REPLACE FUNCTION documents_search_vector_update() RETURNS trigger AS $$
BEGIN
  NEW.search_vector := 
    setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.excerpt, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(NEW.full_text, '')), 'C');
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER tsvector_update BEFORE INSERT OR UPDATE ON documents
  FOR EACH ROW EXECUTE FUNCTION documents_search_vector_update();

\echo 'Trigger created: documents tsvector update'

-- Function to update search_vector for chunks
CREATE OR REPLACE FUNCTION chunks_search_vector_update() RETURNS trigger AS $$
BEGIN
  NEW.search_vector := 
    setweight(to_tsvector('english', COALESCE(NEW.section_heading, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(NEW.content, '')), 'C');
  RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER tsvector_update BEFORE INSERT OR UPDATE ON chunks
  FOR EACH ROW EXECUTE FUNCTION chunks_search_vector_update();

\echo 'Trigger created: chunks tsvector update'
\echo ''

-- ============================================================================
-- Row-Level Security (RLS) Setup
-- ============================================================================
-- Enable RLS on all tables but do NOT enforce policies yet
-- This allows for easier initial setup and testing
-- Production: Uncomment and customize policies below

-- Enable RLS
ALTER TABLE sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE chunks ENABLE ROW LEVEL SECURITY;

\echo 'Row-Level Security enabled on all tables'
\echo ''

-- Grant table access to roles
GRANT SELECT, INSERT, UPDATE, DELETE ON sources, documents, chunks TO app_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON sources, documents, chunks TO app_user;

\echo 'Privileges granted to app_admin and app_user'
\echo ''

-- ============================================================================
-- RLS Policies (Commented Out - Enable in Production)
-- ============================================================================
-- These example policies demonstrate tenant-scoped access control
-- Uncomment and adapt to your authentication scheme

/*
-- Policy: app_admin bypasses RLS
CREATE POLICY admin_all ON sources FOR ALL TO app_admin USING (true);
CREATE POLICY admin_all ON documents FOR ALL TO app_admin USING (true);
CREATE POLICY admin_all ON chunks FOR ALL TO app_admin USING (true);

-- Policy: app_user sees only their tenant's data
-- Assumes current_setting('app.tenant_id') is set by application
CREATE POLICY tenant_isolation ON sources 
  FOR ALL TO app_user
  USING (tenant_id::TEXT = current_setting('app.tenant_id', true));

CREATE POLICY tenant_isolation ON documents
  FOR ALL TO app_user
  USING (tenant_id::TEXT = current_setting('app.tenant_id', true));

CREATE POLICY tenant_isolation ON chunks
  FOR ALL TO app_user
  USING (tenant_id::TEXT = current_setting('app.tenant_id', true));

-- How to use in application:
-- SET LOCAL app.tenant_id = '<user_tenant_id>';
-- ... run queries ...
-- RESET app.tenant_id;
*/

\echo ''
\echo '========================================='
\echo 'Migration 0001 completed successfully!'
\echo '========================================='
\echo ''
\echo 'Next steps:'
\echo '1. Create vector index after ingesting data: '
\echo '   CREATE INDEX idx_chunks_embedding_ivfflat ON chunks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);'
\echo ''
\echo '2. To enable RLS policies, uncomment and customize the policies section in this file'
\echo ''
\echo '3. Run ingestion to populate sources, documents, and chunks'
\echo ''
\echo '4. Monitor query performance:'
\echo '   SELECT * FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;'
\echo ''
