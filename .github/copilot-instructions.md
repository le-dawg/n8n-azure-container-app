# Copilot Instructions for n8n-azure-container-app

## Repository Overview

Terraform IaC for deploying **n8n workflow automation** on **Azure Container Apps** with **Azure OpenAI** (GPT-4o-mini). Cost-effective alternative to AKS deployment.

**Components**: n8n container, PostgreSQL DB, Azure OpenAI, Key Vault, Storage, optional MCP server with NGINX proxy.
**Size**: ~500 lines across 9 .tf files | **Language**: HCL | **Dependencies**: 7 Azure Verified Modules

## Required Versions
- **Terraform**: ~> 1.11 (tested 1.14.0)
- **azurerm**: >= 4, < 5.0.0 (locked 4.26.0)
- **random**: ~> 3.7 (locked 3.7.1)

## Terraform Workflow

### 1. Initialize (REQUIRED FIRST)
**ALWAYS run first**: `terraform init`
- Downloads modules (naming, container apps, key vault, OpenAI, PostgreSQL, storage) and providers (azurerm, random, azapi, modtm, time)
- If "Module not installed" error appears, you forgot this step
- Provider 503 errors are transient - just retry
- Creates `.terraform/` (gitignored), updates `.terraform.lock.hcl`

### 2. Format: `terraform fmt`
Formats .tf files to canonical style. Note: `outputs.tf` has alignment issue that this fixes.
Check without changes: `terraform fmt -check` (exit code 3 = needs formatting)

### 3. Validate: `terraform validate`
Validates syntax locally without Azure connection. No credentials needed. Output: "Success! The configuration is valid."

### 4. Plan: `terraform plan` (Requires Azure Auth)
Creates execution plan. Needs `subscription_id` via `-var="subscription_id=ID"`, `terraform.tfvars` (gitignored), or `TF_VAR_subscription_id` env var.

### 5. Apply: `terraform apply` (Deployment)
Deploys to Azure. Requires confirmation. Takes 10-15 minutes.

## Project Layout

### File Structure (9 .tf files, ~500 lines total)
- **provider.tf**: azurerm config with `subscription_id` variable, `storage_use_azuread = true`
- **variables.tf**: `subscription_id` (required), `location` (default: "eastu2"), `deploy_mcp` (default: false), `enable_telemetry` (default: false), `tags` (optional)
- **main.tf**: Resource group, user-assigned identity, naming module
- **main.aca.tf** (231 lines, most complex): Container App Environment, n8n container (PostgreSQL, Key Vault secrets, File share mount), optional MCP container (2 containers: mcp/azure + nginx reverse proxy)
- **main.kv.tf**: Key Vault with secrets (`openai-key`, `psqladmin-password`), RBAC roles, 60s wait for RBAC propagation
- **main.postgresql.tf**: PostgreSQL v16, random password (16 chars, `_%@` special), `n8n` database UTF8
- **main.storage.tf**: Storage Account with `n8nconfig` File share (2GB, mounted to `/home/node/.n8n`)
- **main.openai.tf**: Azure OpenAI with GPT-4o-mini (2024-07-18), GlobalStandard capacity 8
- **outputs.tf**: Exports `n8n_fqdn_url`, `mcp_endpoint_sse`, OpenAI endpoint/key/deployment, API version (2025-03-01-preview)

### Architecture (6 components)
1. **Naming**: Unique Azure-compliant names
2. **Container Apps**: n8n (0.25 CPU, 0.5Gi, port 5678) + optional MCP with NGINX
3. **PostgreSQL**: n8n backend with SSL
4. **Storage**: Azure Files for persistence
5. **Key Vault**: Secrets storage
6. **OpenAI**: GPT-4o-mini deployment

### Critical Configuration Notes
- **n8n**: Image `docker.io/n8nio/n8n:latest`, HTTP port 5678 (not HTTPS), PostgreSQL SSL enabled
- **MCP NGINX proxy**: `proxy_buffering off`, `gzip off`, `chunked_transfer_encoding off`, Connection header removed - CRITICAL for SSE (see main.aca.tf comments)
- **Known workarounds**: Line 108 main.aca.tf has commented `mount_options` - don't uncomment; Line 90 sets `APPSETTING_WEBSITE_SITE_NAME = "azcli-workaround"` - required

## Validation (No CI/CD pipelines exist)

### Pre-commit Checks
1. `terraform fmt -check` (exit 0)
2. `terraform validate` ("Success!")
3. `terraform init` (if modules/providers changed)

### After Editing .tf Files
1. `terraform fmt` (auto-format)
2. `terraform validate` (syntax check)
3. `terraform plan` (verify plan, needs Azure creds)

## Best Practices

### DO:
- Always `terraform init` after clone or provider version changes
- Run `terraform fmt` before committing
- Run `terraform validate` early to catch syntax errors
- Commit `.terraform.lock.hcl` (ensures reproducible builds)
- Never commit `*.tfvars`, `*.tfstate`, `.terraform/` (see .gitignore)
- Preserve comments explaining workarounds/Azure requirements

### DON'T:
- Skip `terraform init` - most errors stem from this
- Commit secrets - use Key Vault and variables only
- Modify module versions without testing (AVMs version-locked)
- Remove NGINX proxy config in MCP - required for SSE
- Reduce Key Vault 60s RBAC wait - prevents timing issues

### Common Pitfalls
1. "Module not installed": Run `terraform init`
2. Provider 503 errors: Retry `terraform init`
3. Formatting diffs: Run `terraform fmt`
4. Missing subscription_id: Set via `-var`, `.tfvars`, or env var

## Testing (No unit tests exist)
1. Syntax: `terraform validate` (local, no Azure)
2. Format: `terraform fmt -check`
3. Plan: `terraform plan` (needs Azure creds)
4. Full deploy: `terraform apply` in test subscription (~$50-100/month)

## Key Resources
- n8n Azure docs: https://docs.n8n.io/hosting/installation/server-setups/azure/
- Azure Container Apps: https://learn.microsoft.com/en-us/azure/container-apps/
- Azure Verified Modules: https://aka.ms/avm

## Trust These Instructions
Validated by testing all commands. Follow Terraform workflow in order. Most common issues: forgetting `terraform init` and `terraform fmt`. Search only if instructions incomplete/incorrect.
