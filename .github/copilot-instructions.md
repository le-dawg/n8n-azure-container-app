# Copilot Instructions for n8n-azure-container-app

## Repository Overview

This repository contains Terraform Infrastructure as Code (IaC) for deploying n8n workflow automation on Azure Container Apps with Azure OpenAI integration. It provides a cost-effective alternative to Azure Kubernetes Service (AKS) deployments.

**Repository Type**: Terraform Infrastructure as Code (IaC)
**Size**: Small (~14 files, no subdirectories)
**Primary Language**: HashiCorp Configuration Language (HCL)
**License**: MIT

## Key Features
- Deploys n8n workflow automation on Azure Container Apps
- Optional Azure MCP Server container with NGINX reverse proxy
- Azure OpenAI Service with GPT-4o-mini model integration
- PostgreSQL Flexible Server for n8n database
- Azure Key Vault for secrets management
- Azure Storage Account with file share for n8n configuration
- Uses Azure Verified Modules (AVMs) for reliability

## Requirements

### Terraform Version
- **Required**: Terraform ~> 1.11 (version 1.11.x)
- **Azure Provider**: >= 4.0.0, < 5.0.0 (currently locked at 4.26.0)
- **Random Provider**: ~> 3.7 (currently locked at 3.7.1)

### Azure Requirements
- Active Azure subscription with sufficient permissions
- Required subscription ID configured
- Azure CLI authenticated (if running locally)
- Permissions to create resources in the subscription

## Project Structure

### Root Directory Files
```
.
├── .gitignore              # Terraform-specific ignore patterns
├── .terraform.lock.hcl     # Provider version lock file
├── LICENSE                 # MIT License
├── README.md               # Comprehensive project documentation
├── provider.tf             # Terraform and provider configuration
├── variables.tf            # Input variables (location, subscription_id, deploy_mcp, etc.)
├── outputs.tf              # Output values (URLs, endpoints, resource names)
├── main.tf                 # Main resource group, naming, identity
├── main.aca.tf             # Azure Container Apps (n8n and MCP)
├── main.kv.tf              # Azure Key Vault configuration
├── main.openai.tf          # Azure OpenAI Service configuration
├── main.postgresql.tf      # PostgreSQL Flexible Server configuration
└── main.storage.tf         # Azure Storage Account configuration
```

### Configuration Files by Purpose

**Core Infrastructure** (`main.tf`):
- Azure Resource Group with unique naming
- User Assigned Managed Identity for container apps
- Azure naming module for consistent resource names

**Container Apps** (`main.aca.tf`):
- Container App Environment
- n8n container app (always deployed)
- MCP server container app (optional, controlled by `deploy_mcp` variable)
- Container environment storage for n8n configuration
- NGINX reverse proxy configuration for MCP (includes proxy buffering settings)

**Data & Storage** (`main.postgresql.tf`, `main.storage.tf`):
- PostgreSQL Flexible Server v16 with Basic SKU
- Azure Storage Account with file share for n8n config
- Database firewall rules for Azure services

**Security** (`main.kv.tf`):
- Azure Key Vault for secrets
- Stores OpenAI API key and PostgreSQL admin password
- RBAC assignments for container app identity

**AI Services** (`main.openai.tf`):
- Azure OpenAI Service with GPT-4o-mini model
- Model version: 2024-07-18
- GlobalStandard scale type with capacity 8

## Working with Terraform

### Important Notes
**CRITICAL**: This repository has NO build, test, or lint scripts. It is pure Terraform IaC with no CI/CD pipelines or validation workflows.

### Terraform Commands (In Order)

1. **Initialize Terraform** (ALWAYS run first):
   ```bash
   terraform init
   ```
   - Downloads required providers
   - Initializes backend
   - Creates `.terraform` directory (gitignored)
   - Must be run before any other terraform command

2. **Validate Configuration**:
   ```bash
   terraform validate
   ```
   - Checks HCL syntax
   - Validates configuration logic
   - No Azure credentials required

3. **Format Code** (before committing):
   ```bash
   terraform fmt -recursive
   ```
   - Formats all `.tf` files to canonical style
   - Use `-check` flag to verify without modifying: `terraform fmt -check -recursive`

4. **Plan Deployment** (requires Azure credentials):
   ```bash
   terraform plan -var="subscription_id=YOUR_SUBSCRIPTION_ID"
   ```
   - Shows what will be created/modified/destroyed
   - Requires authenticated Azure CLI or credentials
   - Use `-out=tfplan` to save plan for apply

5. **Apply Changes** (deploys infrastructure):
   ```bash
   terraform apply -var="subscription_id=YOUR_SUBSCRIPTION_ID"
   ```
   - Creates/updates Azure resources
   - Requires confirmation unless `-auto-approve` flag used
   - Takes 10-20 minutes for full deployment

6. **Destroy Infrastructure**:
   ```bash
   terraform destroy -var="subscription_id=YOUR_SUBSCRIPTION_ID"
   ```
   - Removes all managed Azure resources
   - Requires confirmation

### Variables

**Required Variables**:
- `subscription_id`: Azure Subscription ID (no default)

**Optional Variables** (with defaults):
- `location`: Azure region (default: "eastu2")
- `deploy_mcp`: Deploy MCP container (default: false)
- `enable_telemetry`: Enable AVM telemetry (default: false)
- `tags`: Custom tags map (default: null)

**Variable Files**: All `*.tfvars` and `*.tfvars.json` files are gitignored for security.

### State Management

- **State File**: `terraform.tfstate` (gitignored)
- **State Lock**: `.terraform.tfstate.lock.info` (gitignored)
- No remote backend configured by default
- State contains sensitive data (passwords, keys)

## Making Changes

### When Modifying Terraform Code

1. **Always run `terraform fmt -recursive`** before committing to ensure consistent formatting
2. **Run `terraform validate`** to check syntax and configuration validity
3. **Test with `terraform plan`** if you have Azure access (optional but recommended)
4. **Do NOT commit** the following (already in .gitignore):
   - `.terraform/` directory
   - `*.tfstate` and `*.tfstate.*` files
   - `*.tfvars` and `*.tfvars.json` files
   - Lock info files
   - `override.tf` files

### Common Modification Patterns

**Adding a new Azure resource**:
- Create a new `main.*.tf` file or add to existing one
- Use Azure Verified Modules when available
- Reference existing resources using Terraform interpolation
- Add any new outputs to `outputs.tf`
- Add new variables to `variables.tf` if needed

**Modifying container configuration**:
- Edit `main.aca.tf` for n8n or MCP containers
- Update environment variables in the `env` blocks
- Modify resource allocations (CPU, memory) as needed
- Test changes with `terraform plan`

**Adding secrets**:
- Add to Key Vault secrets in `main.kv.tf`
- Reference in container env using `secret_name`
- Ensure proper RBAC assignments exist

### Architecture-Specific Constraints

1. **Resource Naming**: Uses Azure naming module for unique names. Don't hardcode resource names.
2. **Managed Identity**: Single user-assigned identity shared by all container apps and Key Vault access.
3. **PostgreSQL**: Configured with Azure firewall access (0.0.0.0). Public network access required for Container Apps.
4. **Storage**: Azure File share mounted to n8n container at `/home/node/.n8n`.
5. **MCP Proxy**: If deploying MCP, NGINX config disables buffering for SSE (Server-Sent Events).

## Module Dependencies

This repository uses the following Azure Verified Modules (AVMs):

| Module | Version | Purpose |
|--------|---------|---------|
| Azure/naming/azurerm | 0.4.0 | Resource naming convention |
| Azure/avm-res-app-containerapp/azurerm | 0.4.0 | Container Apps |
| Azure/avm-res-keyvault-vault/azurerm | 0.10.0 | Key Vault |
| Azure/avm-res-cognitiveservices-account/azurerm | 0.7.0 | OpenAI Service |
| Azure/avm-res-dbforpostgresql-flexibleserver/azurerm | 0.1.4 | PostgreSQL |
| Azure/avm-res-storage-storageaccount/azurerm | 0.5.0 | Storage Account |

**Note**: Module versions are locked in `.terraform.lock.hcl`. Run `terraform init -upgrade` to update.

## Validation & Best Practices

### Pre-Commit Checklist
1. Run `terraform fmt -recursive` to format code
2. Run `terraform validate` to check configuration
3. Review changes with `git diff`
4. Ensure no sensitive data in commits
5. Verify `.gitignore` patterns are working

### Code Style
- Use consistent indentation (2 spaces, handled by `terraform fmt`)
- Group related resources in same file
- Use descriptive resource names
- Add comments for complex configurations
- Use variables for values that might change

### Security Considerations
- **Never commit**: `*.tfvars`, state files, or credentials
- Key Vault secrets are managed by Terraform but values aren't stored in code
- Random password generated at apply time for PostgreSQL
- Managed identities used instead of credentials where possible
- Public network access required for Container Apps to reach PostgreSQL/Storage

## Troubleshooting

### Common Issues

**"Error: Unsupported Terraform version"**
- Solution: Ensure Terraform 1.11.x is installed

**"Error: Unable to find provider"**
- Solution: Run `terraform init` to download providers

**Format check fails in CI**
- Solution: Run `terraform fmt -recursive` locally before commit

**Plan/Apply requires credentials**
- Solution: Authenticate with Azure CLI: `az login`
- Or set environment variables: `ARM_SUBSCRIPTION_ID`, `ARM_CLIENT_ID`, etc.

**"Error: building account"**
- Solution: Ensure `subscription_id` variable is provided

## Additional Resources

- [Terraform AzureRM Provider Docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Verified Modules](https://aka.ms/avm)
- [n8n Documentation](https://docs.n8n.io/)
- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)

## Trust These Instructions

These instructions are comprehensive and validated. Only search for additional information if:
- Instructions are incomplete for your specific use case
- You encounter an error not covered here
- You need Azure-specific documentation beyond Terraform
- Instructions are found to be incorrect

When in doubt, start with `terraform fmt`, `terraform validate`, and `terraform plan` to validate changes.
