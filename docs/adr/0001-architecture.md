# ADR-0001: Azure-Native RAG Stack Architecture

**Status**: Accepted  
**Date**: 2025-11-24  
**Authors**: GitHub Copilot (gpt-5-high)

## Context

This repository initially deployed n8n as an Azure Container App (ACA) with basic PostgreSQL support. The business requirement has evolved to implement a complete, production-grade RAG (Retrieval-Augmented Generation) stack for compliance document processing, entirely on Azure-native components within a single subscription and resource group.

### Key Requirements
- **Data Residency**: All data must remain in EU regions (primarily `northeurope`)
- **Self-Hosted**: No external cloud services (e.g., no Supabase Cloud)
- **Cost-Optimized**: Designed for ≤5 users, ≤10 RAG requests/sec
- **Multi-Environment Ready**: Structure supports trivial addition of stage/prod environments
- **Security-First**: No secrets in code, parameterized configuration, RLS scaffolding

## Decision

We are evolving the repository from "n8n-only ACA" to a comprehensive RAG stack with the following architecture:

### Target Architecture Components

#### 1. Database Layer
**Azure Database for PostgreSQL Flexible Server**
- **SKU**: Burstable B_Standard_B1ms (1-2 vCPUs, 2-4 GB RAM)
- **Region**: northeurope
- **Extensions**: pgvector (for embeddings), pg_trgm, pg_stat_statements (for FTS/BM25)
- **Access Control**: 
  - Firewall restricted to ACA environment and Azure Functions
  - RLS scaffolding with app_admin and app_user roles
  - Tenant-scoped access patterns (commented templates)
- **Schema**:
  - `sources` table: File metadata, hashes, tenant_id
  - `documents` table: Logical documents, full_text, classification
  - `chunks` table: Text chunks, embeddings (VECTOR), page numbers

**Design Rationale**: 
- Azure Postgres Flexible Server provides managed pgvector support
- External DB allows Supabase to remain stateless and easily replaceable
- Burstable SKU provides cost optimization while supporting load requirements
- RLS scaffolding provides security foundation without immediate complexity

#### 2. Container Apps Layer
**Single Azure Container Apps Environment** in northeurope hosting:

**a. n8n Workflow Automation**
- Container: `n8nio/n8n:latest`
- Resources: 0.25 CPU, 0.5Gi memory
- Persistence: Azure Files mount at `/home/node/.n8n`
- Role: Orchestration hub for RAG pipeline
- Auth: Basic auth + optional IP allowlist

**b. Supabase Self-Hosted Stack**
- Components deployed as separate ACAs:
  - **supabase-auth** (GoTrue): Authentication service
  - **supabase-rest** (PostgREST): REST API over Postgres
  - **supabase-storage**: Object storage (optional, feature-flagged)
  - **supabase-studio**: Admin UI (optional, feature-flagged)
- All connect to external Azure Postgres Flexible Server
- Configuration via environment variables (no secrets in code)
- JWT secrets passed via Key Vault references

**Design Rationale**:
- Self-hosted Supabase ensures data sovereignty
- Separate ACAs per component allows independent scaling
- External Postgres reduces container complexity and improves reliability
- Optional components reduce cost in dev environment

#### 3. Azure Functions Layer
**a. Document Ingestion Function** (Python, Consumption Plan)
- **Trigger**: HTTP (scheduled by n8n)
- **Responsibilities**:
  - Authenticate to SharePoint via Managed Identity
  - Parse documents (PDF/DOCX) via Docling
  - Chunk text and generate embeddings (Cohere)
  - Idempotent upsert to Postgres (hash-based deduplication)
- **Configuration**:
  - POSTGRES_URL (connection string or Managed Identity)
  - EMBEDDING_DIMENSION (default: 1536)
  - EMBEDDING_PROVIDER (default: "cohere")
  - COHERE_API_KEY (slot only, value from Key Vault)
  - SharePoint site/library/folder parameters
  - LMNR_PROJECT_API_KEY, LMNR_URL (Laminar observability)

**b. BM25/Hybrid Retrieval Function** (Python, Consumption Plan)
- **Trigger**: HTTP with function key auth
- **Responsibilities**:
  - Query Postgres for vector similarity candidates (pgvector)
  - Query Postgres for BM25/FTS candidates (pg_trgm, ts_rank)
  - Merge and score with configurable fusion:
    - **Weighted Sum**: `hybrid_score = α × vector_norm + (1-α) × bm25_norm`
    - **RRF**: `RRF(d) = Σ 1/(k + rank_i(d))`
  - Optional reranking via Azure AI Foundry endpoints
  - Return ranked documents/chunks for LLM context
- **Configuration**:
  - POSTGRES_URL
  - EMBEDDING_DIMENSION
  - HYBRID_ALPHA (default: 0.5, for weighted sum)
  - FUSION_STRATEGY (default: "weighted_sum", alt: "rrf")
  - RERANKER_ENABLED (bool)
  - RERANKER_MODEL ("cohere" or "bge")
  - RERANKER_ENDPOINT_URL
  - LMNR_PROJECT_API_KEY, LMNR_URL

**Design Rationale**:
- HTTP triggers give n8n full control over scheduling
- Consumption plan optimizes cost for low-volume workloads
- Managed Identity eliminates credential management
- Configurable fusion strategies allow experimentation
- Function-level auth provides basic security (upgradeable to private endpoints)

#### 4. AI Layer
**Azure AI Foundry Hub + Project** (prefer northeurope, fallback westeurope)
- **Reranker Endpoints** (serverless):
  - **Cohere Rerank v3.5**: For high-quality semantic reranking
  - **BGE-based reranker**: TEI-based alternative for cost/latency optimization
- **Access**: Endpoint URLs and keys exposed as env var slots
- **Integration**: Called by BM25 function and n8n workflows

**Design Rationale**:
- Serverless endpoints minimize cost (pay-per-use)
- Two rerankers provide flexibility for A/B testing
- Azure AI Foundry keeps everything in Azure ecosystem
- Region fallback documented for model availability constraints

#### 5. Frontend Layer
**Azure Static Web App** (broen-lab-ui-azure)
- **Auth**: Entra ID (M365 work accounts)
- **Backend Integration**: Routes to n8n or API proxy
- **Build**: GitHub Actions pipeline (existing, preserved)
- **Configuration**: LLM_PROVIDER and endpoint URL via Static Web App config

**Design Rationale**:
- Static Web App provides cheap, scalable hosting
- Entra ID integration ensures org-only access
- Direct n8n integration reduces architecture complexity

#### 6. Observability Layer
**Laminar Cloud** (free tier for dev)
- **Integration**: Via SDK in Functions and n8n workflows
- **Configuration**: 
  - LMNR_PROJECT_API_KEY (from Laminar Cloud project)
  - LMNR_URL (cloud or self-hosted instance)
- **Spans**: LLM calls, tool calls, RAG steps tracked end-to-end

**Design Rationale**:
- Cloud-based observability reduces operational overhead
- Free tier sufficient for dev environment
- Easy migration to self-hosted in future if needed

### Region Strategy

**Primary Region**: `northeurope`
- All databases, compute, and storage
- ACA environment
- Azure Functions

**Fallback Regions** (if model unavailable in northeurope):
- `westeurope`: Azure AI Foundry models
- Clearly documented in comments and README

### Networking & Security

**Dev Environment** (current implementation):
- Public networking with strict firewall rules
- ACA ingress: n8n and Supabase (external_enabled = true)
- Postgres: Firewall allowlist for ACA + Functions
- Functions: Function key auth, optional IP restrictions
- Static Web App: Entra ID auth, no anonymous access

**Future Hardening** (documented, not implemented):
- VNet-integrated ACA environment
- Private endpoints for Postgres and AI Foundry
- Azure Front Door as single public entry point
- Managed Identity for all DB access

### Secrets Management

**Current Approach**:
- All secrets parameterized as Terraform variables
- Sensitive values stored in Azure Key Vault
- ACA and Functions reference secrets via Key Vault integration
- n8n credential store used for dev-time secrets

**Values Parameterized**:
- DB passwords
- Supabase JWT secrets
- OpenAI, Cohere, BGE API keys
- Laminar project API key
- M365/Entra tenant IDs
- SharePoint site/library identifiers

**Key Principle**: No secrets in Git, ever.

### RAG Schema Design

**Embedding Configuration**:
- `embedding_dimension` variable (default: 1536 for Cohere/OpenAI)
- Exported as EMBEDDING_DIMENSION env var to all components

**Tables**:
```sql
-- sources: Raw file metadata
CREATE TABLE sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    doc_type TEXT,
    hash TEXT NOT NULL UNIQUE, -- SHA256 for idempotency
    tenant_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- documents: Logical documents
CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id UUID REFERENCES sources(id),
    title TEXT,
    full_text TEXT,
    classification TEXT,
    effective_date DATE,
    version TEXT,
    tenant_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- chunks: Text chunks with embeddings
CREATE TABLE chunks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID REFERENCES documents(id),
    chunk_index INTEGER NOT NULL,
    content TEXT NOT NULL,
    embedding VECTOR({embedding_dimension}),
    page_number INTEGER,
    section_heading TEXT,
    tenant_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Indexes**:
- Vector index: IVFFlat (default) or HNSW (configurable)
  - `vector_index_type` variable
  - `vector_index_params` map for tuning
- FTS indexes: GIN on chunks.content for BM25
- B-tree indexes on foreign keys, tenant_id, timestamps

**RLS**:
- Roles: `app_admin` (bypasses RLS), `app_user` (subject to RLS)
- Policies: Commented examples for tenant-scoped access
- Not enforced by default to allow easier dev setup

### Terraform Structure

**New Modular Layout**:
```
/
├── main.tf              # Environment wiring
├── provider.tf          # Terraform & provider config
├── backend.tf           # State backend config (to be added)
├── variables.tf         # All input variables
├── outputs.tf           # All outputs
├── modules/
│   ├── aca_app/         # Generic ACA module
│   ├── postgres_flexible/  # Postgres with pgvector
│   ├── n8n/             # n8n-specific wrapper
│   ├── supabase/        # Supabase component group
│   ├── function_app_python/  # Python Function template
│   ├── ai_reranker/     # AI Foundry + endpoints
│   └── static_web_app/  # Frontend deployment
├── db/
│   ├── 0001_base.sql    # Base schema + indexes
│   └── README.md        # Migration instructions
└── docs/
    ├── plan.md          # Deployment guide
    └── adr/
        └── 0001-architecture.md  # This document
```

**Module Design Principles**:
- Self-contained with clear inputs/outputs
- No environment-specific hard-coding
- Sane defaults for dev, overridable for prod
- Heavy inline comments explaining purpose and usage

### Multi-Environment Strategy

**Current**: Single dev environment

**Future** (trivial to add):
- Terraform workspaces or separate state files
- Environment-specific `.tfvars` files:
  - `envs/dev.tfvars`
  - `envs/stage.tfvars`
  - `envs/prod.tfvars`
- Backend state key pattern: `envs/{environment}/main.tfstate`
- No module changes required, only variable values

### Migration Path from Current State

1. **Refactor existing resources** into modules
2. **Add new modules** for Supabase, Functions, AI Foundry, Static Web App
3. **Change region** from eastu2 to northeurope
4. **Enable pgvector** on existing Postgres (requires recreation or extension config)
5. **Add RAG schema** via manual migration (Terraform creates DB, ops team runs SQL)
6. **Deploy new components** incrementally with feature flags
7. **Validate** at each step with terraform plan

## Consequences

### Positive
- ✅ Complete Azure-native RAG stack
- ✅ EU data residency guaranteed
- ✅ Cost-optimized for small teams
- ✅ Self-hosted components ensure data sovereignty
- ✅ Modular Terraform enables easy environment proliferation
- ✅ Comprehensive parameterization supports secure credential management
- ✅ Clear migration path from current state

### Negative
- ⚠️ Increased complexity vs. n8n-only deployment
- ⚠️ More moving parts to monitor and maintain
- ⚠️ Manual DB migration steps required (not fully automated in Terraform)
- ⚠️ Breaking change: region switch from eastu2 to northeurope (requires recreation)
- ⚠️ Self-hosted Supabase requires more operational knowledge than cloud offering

### Mitigations
- Heavy documentation and inline comments reduce learning curve
- Modular structure isolates changes and reduces blast radius
- Feature flags allow incremental rollout
- Observability (Laminar) provides visibility into complex interactions
- RLS scaffolding provides security foundation without immediate enforcement

## Alternatives Considered

### 1. Use Supabase Cloud
**Rejected**: Violates data sovereignty requirement. All data must stay in Azure subscription.

### 2. Deploy Postgres in ACA container
**Rejected**: Stateful container adds complexity, reduces reliability, and limits scalability. Azure Postgres Flexible Server provides better guarantees.

### 3. Use Azure Cognitive Search instead of pgvector
**Rejected**: Adds another service and cost. pgvector on Postgres provides sufficient performance for scale and keeps stack simpler.

### 4. Deploy everything in Kubernetes (AKS)
**Rejected**: Cost prohibitive for small scale. ACA provides sufficient capabilities at fraction of cost.

### 5. Use Azure Functions for entire backend
**Rejected**: n8n provides better orchestration and low-code workflow capabilities. Functions used only for compute-heavy tasks (ingestion, BM25).

## References

- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure Database for PostgreSQL - pgvector](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/how-to-use-pgvector)
- [Supabase Self-Hosting Guide](https://supabase.com/docs/guides/self-hosting)
- [Azure AI Foundry](https://learn.microsoft.com/en-us/azure/ai-studio/)
- [Laminar Cloud](https://www.laminar.sh/)

---

**Next Steps**: Proceed with implementation following the phased plan in docs/plan.md.
