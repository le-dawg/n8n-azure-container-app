# Azure-Native RAG Stack - Deployment Plan

## Overview

This document provides step-by-step instructions for deploying the complete Azure-native RAG stack for compliance document processing. The stack includes n8n, self-hosted Supabase, pgvector-enabled PostgreSQL, Azure Functions for ingestion and retrieval, Azure AI Foundry rerankers, and a Static Web App frontend.

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Subscription (EU)                       │
│                 Resource Group: northeurope                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────────────────────────────────────────┐       │
│  │   Azure Container Apps Environment (northeurope)     │       │
│  │                                                       │       │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │       │
│  │  │   n8n    │  │ Supabase │  │ Supabase │          │       │
│  │  │          │  │   Auth   │  │   REST   │          │       │
│  │  └──────────┘  └──────────┘  └──────────┘          │       │
│  │       │              │              │                │       │
│  └───────┼──────────────┼──────────────┼────────────────┘       │
│          │              │              │                         │
│          │              └──────┬───────┘                         │
│          │                     │                                 │
│          ▼                     ▼                                 │
│  ┌───────────────────────────────────────┐                      │
│  │  Azure Database for PostgreSQL        │                      │
│  │  Flexible Server (pgvector enabled)   │                      │
│  │  - n8n database                        │                      │
│  │  - RAG schema (sources, docs, chunks) │                      │
│  └───────────────────────────────────────┘                      │
│          ▲                     ▲                                 │
│          │                     │                                 │
│  ┌───────┴────┐       ┌────────┴─────┐                          │
│  │ Ingestion  │       │   BM25/      │                          │
│  │  Function  │       │   Hybrid     │                          │
│  │  (Python)  │       │  Function    │                          │
│  └────────────┘       └──────────────┘                          │
│       │                       │                                  │
│       │                       ▼                                  │
│       │              ┌─────────────────┐                         │
│       │              │ Azure AI Foundry│                         │
│       │              │  - Cohere       │                         │
│       │              │    Rerank v3.5  │                         │
│       │              │  - BGE Reranker │                         │
│       │              └─────────────────┘                         │
│       │                                                           │
│       ▼                                                           │
│  ┌─────────────────────────────┐                                │
│  │   SharePoint (Other Tenant) │                                │
│  │   - Source Documents        │                                │
│  └─────────────────────────────┘                                │
│                                                                   │
│  ┌─────────────────────────────┐                                │
│  │  Azure Static Web App        │                                │
│  │  (broen-lab-ui-azure)        │                                │
│  │  - Entra ID Auth             │                                │
│  │  - Routes to n8n backend     │                                │
│  └─────────────────────────────┘                                │
│                                                                   │
│  ┌─────────────────────────────┐                                │
│  │   Azure Key Vault            │                                │
│  │   - DB passwords             │                                │
│  │   - API keys                 │                                │
│  │   - JWT secrets              │                                │
│  └─────────────────────────────┘                                │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘

         External: Laminar Cloud (observability)
                   Cohere API (embeddings)
```

## Prerequisites

### 1. Azure Resources
- Azure subscription with Owner or Contributor access
- Azure CLI installed and authenticated
- Terraform >= 1.8, < 2.0 installed
- Sufficient quota in northeurope region for:
  - Container Apps (4+ containers)
  - PostgreSQL Flexible Server
  - 2 Azure Functions (Consumption Plan)
  - Azure AI Foundry hub/project
  - Static Web App

### 2. External Services
- **Laminar Cloud** (optional, for observability):
  - Sign up at https://www.laminar.sh/
  - Create a project and obtain API key
- **Cohere** (for embeddings):
  - Sign up at https://cohere.com/
  - Obtain API key
- **SharePoint** (for document source):
  - Note the tenant ID, site ID, library ID, and folder path
  - Ensure service principal or managed identity has read access

### 3. GitHub (for Static Web App)
- Repository with broen-lab-ui-azure frontend code
- GitHub Actions enabled

## Environment Configuration

### 1. Create Backend Storage for Terraform State

```bash
# Variables
RESOURCE_GROUP="tfstate-rg"
STORAGE_ACCOUNT="tfstate$(openssl rand -hex 4)"
CONTAINER_NAME="tfstate"
LOCATION="northeurope"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create storage account
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --encryption-services blob

# Create container
az storage container create \
  --name $CONTAINER_NAME \
  --account-name $STORAGE_ACCOUNT
```

### 2. Configure Backend

Create `backend.tf` with your values:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstate<RANDOM>"
    container_name       = "tfstate"
    key                  = "envs/dev/main.tfstate"
  }
}
```

### 3. Create Environment Variables File

Create `envs/dev.tfvars`:

```hcl
# Basic Configuration
environment       = "dev"
location          = "northeurope"
subscription_id   = "<YOUR_SUBSCRIPTION_ID>"
enable_telemetry  = false

# Feature Flags
deploy_mcp                = false
enable_supabase_studio    = false
enable_supabase_storage   = false
enable_reranker           = true

# Database Configuration
postgres_sku_name         = "B_Standard_B1ms"
postgres_version          = 16
postgres_storage_mb       = 32768
postgres_backup_retention_days = 7

# Embedding Configuration
embedding_dimension       = 1536
embedding_provider        = "cohere"

# Vector Index Configuration
vector_index_type         = "ivfflat"
vector_index_params = {
  lists = 100
}

# Hybrid Search Configuration
hybrid_alpha              = 0.5
fusion_strategy           = "weighted_sum"  # or "rrf"

# Reranker Configuration
reranker_model            = "cohere"  # or "bge"

# Tags
tags = {
  environment = "dev"
  project     = "rag-compliance"
  managed_by  = "terraform"
}

# Secrets (via environment variables or Key Vault)
# DO NOT PUT ACTUAL VALUES HERE - these are just slots
# Set via TF_VAR_* environment variables or populate in Key Vault

# Supabase Configuration
# supabase_jwt_secret       = ""  # Generate: openssl rand -base64 32
# supabase_anon_key         = ""  # Generate via Supabase tooling
# supabase_service_role_key = ""  # Generate via Supabase tooling

# External API Keys (provide via env vars)
# cohere_api_key            = ""
# openai_api_key            = ""
# laminar_api_key           = ""

# SharePoint Configuration
# sharepoint_tenant_id      = ""
# sharepoint_site_id        = ""
# sharepoint_library_id     = ""
# sharepoint_folder_path    = ""

# Entra ID Configuration
# entra_tenant_id           = ""
# entra_client_id           = ""
```

### 4. Set Secret Environment Variables

```bash
# Supabase secrets
export TF_VAR_supabase_jwt_secret=$(openssl rand -base64 32)
export TF_VAR_supabase_anon_key="<GENERATE_VIA_SUPABASE_TOOLING>"
export TF_VAR_supabase_service_role_key="<GENERATE_VIA_SUPABASE_TOOLING>"

# API keys
export TF_VAR_cohere_api_key="<YOUR_COHERE_API_KEY>"
export TF_VAR_openai_api_key="<YOUR_OPENAI_API_KEY>"
export TF_VAR_laminar_api_key="<YOUR_LAMINAR_API_KEY>"

# SharePoint
export TF_VAR_sharepoint_tenant_id="<TENANT_ID>"
export TF_VAR_sharepoint_site_id="<SITE_ID>"
export TF_VAR_sharepoint_library_id="<LIBRARY_ID>"
export TF_VAR_sharepoint_folder_path="<FOLDER_PATH>"

# Entra ID
export TF_VAR_entra_tenant_id="<YOUR_TENANT_ID>"
export TF_VAR_entra_client_id="<YOUR_CLIENT_ID>"
```

## Deployment Steps

### Phase 1: Initialize and Validate

```bash
cd /path/to/n8n-azure-container-app

# Initialize Terraform
terraform init

# Format all files
terraform fmt -recursive

# Validate configuration
terraform validate

# Review plan
terraform plan -var-file=envs/dev.tfvars -out=tfplan
```

### Phase 2: Deploy Core Infrastructure

```bash
# Deploy (this will take 15-30 minutes)
terraform apply tfplan

# Capture outputs
terraform output -json > outputs.json
```

### Phase 3: Database Schema Setup

```bash
# Get database connection string from Key Vault
DB_PASSWORD=$(az keyvault secret show \
  --vault-name $(terraform output -raw key_vault_name) \
  --name psqladmin-password \
  --query value -o tsv)

DB_HOST=$(terraform output -raw postgres_fqdn)

# Connect to database
psql "host=$DB_HOST port=5432 dbname=n8n user=psqladmin password=$DB_PASSWORD sslmode=require"

# Run migrations (from db/ directory)
\i db/0001_base.sql

# Verify extensions
SELECT * FROM pg_extension WHERE extname IN ('vector', 'pg_trgm');

# Verify tables
\dt

# Exit
\q
```

### Phase 4: Verify Deployments

#### Check n8n
```bash
N8N_URL=$(terraform output -raw n8n_fqdn_url)
echo "n8n URL: $N8N_URL"
curl -I $N8N_URL
```

#### Check Supabase
```bash
SUPABASE_URL=$(terraform output -raw supabase_rest_url)
echo "Supabase REST URL: $SUPABASE_URL"
curl -I $SUPABASE_URL
```

#### Check Functions
```bash
INGESTION_URL=$(terraform output -raw ingestion_function_url)
BM25_URL=$(terraform output -raw bm25_function_url)

echo "Ingestion Function: $INGESTION_URL"
echo "BM25 Function: $BM25_URL"

# Test ingestion function (requires function key)
INGESTION_KEY=$(az functionapp keys list \
  --name $(terraform output -raw ingestion_function_name) \
  --resource-group $(terraform output -raw resource_group_name) \
  --query functionKeys.default -o tsv)

curl -X POST "$INGESTION_URL?code=$INGESTION_KEY" \
  -H "Content-Type: application/json" \
  -d '{"test": true}'
```

### Phase 5: Configure n8n

1. **Access n8n**:
   - Navigate to the n8n URL from output
   - Set up admin credentials on first access

2. **Add Credentials**:
   - **PostgreSQL**: For direct DB access if needed
   - **Azure OpenAI**: From Terraform outputs
   - **Cohere**: For embeddings (from env var)
   - **Azure Function**: For ingestion and BM25 functions

3. **Import Workflows**:
   - Document ingestion workflow
   - RAG retrieval workflow
   - Scheduled refresh workflow

### Phase 6: Configure Static Web App

```bash
STATIC_WEB_APP_NAME=$(terraform output -raw static_web_app_name)

# Get deployment token
DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
  --name $STATIC_WEB_APP_NAME \
  --resource-group $(terraform output -raw resource_group_name) \
  --query properties.apiKey -o tsv)

# Add to GitHub repository secrets as AZURE_STATIC_WEB_APPS_API_TOKEN

# Configure environment variables in Azure Portal:
# - N8N_ENDPOINT: <n8n_url>
# - SUPABASE_URL: <supabase_rest_url>
# - SUPABASE_ANON_KEY: <from Key Vault>
```

### Phase 7: Test End-to-End RAG Pipeline

1. **Trigger Ingestion**:
   ```bash
   # Via n8n workflow or direct function call
   curl -X POST "$INGESTION_URL?code=$INGESTION_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "folder_path": "<SHAREPOINT_FOLDER>",
       "force_refresh": false
     }'
   ```

2. **Test Retrieval**:
   ```bash
   BM25_KEY=$(az functionapp keys list \
     --name $(terraform output -raw bm25_function_name) \
     --resource-group $(terraform output -raw resource_group_name) \
     --query functionKeys.default -o tsv)

   curl -X POST "$BM25_URL?code=$BM25_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "query": "What are the compliance requirements for data retention?",
       "top_k": 10,
       "use_reranker": true
     }'
   ```

3. **Test via Frontend**:
   - Navigate to Static Web App URL
   - Authenticate with Entra ID
   - Submit a query and verify results

## Monitoring and Observability

### Laminar Cloud

1. **View Traces**:
   - Navigate to https://app.laminar.sh/
   - Select your project
   - View traces for ingestion and retrieval operations

2. **Check Metrics**:
   - Latency percentiles
   - Error rates
   - Token usage

### Azure Monitor

```bash
# View Container App logs
az containerapp logs show \
  --name $(terraform output -raw n8n_container_app_name) \
  --resource-group $(terraform output -raw resource_group_name) \
  --follow

# View Function logs
az functionapp log tail \
  --name $(terraform output -raw bm25_function_name) \
  --resource-group $(terraform output -raw resource_group_name)
```

## Adding New Environments (stage/prod)

### 1. Create Environment Variable File

```bash
cp envs/dev.tfvars envs/stage.tfvars
# Edit envs/stage.tfvars with stage-specific values
```

### 2. Update Backend Key

In your Terraform commands, specify a different state key:

```bash
terraform init -backend-config="key=envs/stage/main.tfstate"
```

Or use Terraform workspaces:

```bash
terraform workspace new stage
terraform workspace select stage
```

### 3. Deploy

```bash
terraform plan -var-file=envs/stage.tfvars
terraform apply -var-file=envs/stage.tfvars
```

**Note**: No module changes required! All environment differences are captured in `.tfvars` files.

## Troubleshooting

### Issue: pgvector extension not found

**Solution**: Ensure extension is enabled in Postgres:
```sql
CREATE EXTENSION IF NOT EXISTS vector;
SELECT * FROM pg_extension WHERE extname = 'vector';
```

### Issue: Supabase containers not connecting to Postgres

**Solution**: Check firewall rules and connection strings:
```bash
# Verify firewall allows ACA environment
az postgres flexible-server firewall-rule list \
  --name $(terraform output -raw postgres_name) \
  --resource-group $(terraform output -raw resource_group_name)
```

### Issue: Function returns 401/403

**Solution**: Verify function key and auth level:
```bash
az functionapp config show \
  --name <FUNCTION_NAME> \
  --resource-group <RG_NAME> \
  --query "authSettings"
```

### Issue: Static Web App authentication fails

**Solution**: Verify Entra ID app registration:
- Check redirect URIs include Static Web App URL
- Ensure API permissions are granted
- Verify client secret is not expired

## Cost Estimation (Dev Environment)

| Resource | SKU | Estimated Monthly Cost (USD) |
|----------|-----|------------------------------|
| Container Apps (4 apps) | 0.25 vCPU, 0.5Gi each | ~$30 |
| PostgreSQL Flexible | B_Standard_B1ms | ~$15 |
| Azure Functions (2) | Consumption | ~$5 |
| Azure AI Foundry | Serverless (pay-per-use) | ~$10 |
| Static Web App | Free tier | $0 |
| Storage Account | Standard LRS | ~$2 |
| Key Vault | Standard | ~$1 |
| **Total** | | **~$63/month** |

**Notes**:
- Costs vary based on usage patterns
- AI Foundry costs depend on reranking call volume
- Function costs based on ~1000 executions/month
- Production environments will cost more due to higher SKUs and redundancy

## Security Hardening (Production Checklist)

- [ ] Enable VNet integration for ACA environment
- [ ] Configure private endpoints for PostgreSQL
- [ ] Configure private endpoints for AI Foundry
- [ ] Restrict Function Apps to VNet only
- [ ] Enable Azure Front Door with WAF
- [ ] Enable Managed Identity for all DB access
- [ ] Implement RLS policies on database tables
- [ ] Enable Azure Monitor alerts for anomalies
- [ ] Rotate secrets via Key Vault periodic rotation
- [ ] Enable Azure DDoS Protection Standard
- [ ] Configure network security groups
- [ ] Enable Azure Security Center recommendations
- [ ] Implement role-based access control (RBAC) for all resources
- [ ] Enable audit logging on all resources

## References

- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [PostgreSQL pgvector](https://github.com/pgvector/pgvector)
- [Supabase Self-Hosting](https://supabase.com/docs/guides/self-hosting)
- [Azure AI Foundry](https://learn.microsoft.com/en-us/azure/ai-studio/)
- [n8n Documentation](https://docs.n8n.io/)

## Support

For issues or questions:
1. Check this deployment guide
2. Review ADR-0001 in docs/adr/
3. Examine Terraform inline comments
4. Consult Azure documentation links above
5. Open an issue in the repository

---

**Last Updated**: 2025-11-24  
**Version**: 1.0.0
