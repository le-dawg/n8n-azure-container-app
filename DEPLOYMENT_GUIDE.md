# Quick Start Deployment Guide

This guide provides step-by-step instructions to deploy the minimal Azure infrastructure.

## Prerequisites

1. Azure subscription with appropriate permissions
2. Terraform >= 1.8 installed
3. Azure CLI (optional, for authentication)
4. Text editor for configuration files

## Step 1: Configure Backend Storage

Create backend storage for Terraform state (one-time setup):

```bash
# Set variables
RESOURCE_GROUP="tfstate-rg"
STORAGE_ACCOUNT="yourtfstate$(date +%s)"  # Must be globally unique
CONTAINER_NAME="tfstate"
LOCATION="northeurope"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create storage account
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS

# Create blob container
az storage container create \
  --name $CONTAINER_NAME \
  --account-name $STORAGE_ACCOUNT
```

## Step 2: Configure Variables

Copy and edit the backend configuration:

```bash
cp backend.hcl.template backend.hcl
```

Edit `backend.hcl`:
```hcl
resource_group_name  = "tfstate-rg"
storage_account_name = "your-storage-account-name"  # From Step 1
container_name       = "tfstate"
key                  = "dev.terraform.tfstate"
```

Copy and edit the variables file:

```bash
cp terraform.tfvars.template terraform.tfvars
```

Edit `terraform.tfvars` with your actual values:
```hcl
subscription_id = "your-azure-subscription-id"

# Strong password for PostgreSQL
postgres_admin_password = "YourSecurePassword123!"

# External OpenAI endpoint (in separate tenant)
external_openai_endpoint        = "https://your-openai.openai.azure.com/"
external_openai_api_key         = "your-openai-api-key"
external_openai_deployment_name = "gpt-4"  # or your model name

# Cohere API key (cloud API or leave empty for Azure deployment)
cohere_rerank_api_key = "your-cohere-api-key-or-empty"

# IP whitelisting (your public IP)
allowed_ip_ranges = ["YOUR_IP/32"]  # Get with: curl ifconfig.me

# Optional: Custom tags
tags = {
  Environment = "Development"
  Project     = "Haystack-n8n"
}
```

**Security**: Never commit `backend.hcl` or `terraform.tfvars` to version control!

## Step 3: Initialize Terraform

```bash
# Initialize with backend configuration
terraform init -backend-config=backend.hcl

# You should see: "Terraform has been successfully initialized!"
```

## Step 4: Review Plan

```bash
# Generate and review execution plan
terraform plan -var-file=terraform.tfvars -out=tfplan

# Review the plan carefully
# Expected resources: ~15-20 resources
```

## Step 5: Apply Configuration

```bash
# Apply the plan
terraform apply tfplan

# This will take 10-15 minutes
# Type 'yes' when prompted (if not using -out=tfplan)
```

## Step 6: Initialize PostgreSQL Schema

After successful apply, initialize the database schema:

```bash
# Get PostgreSQL server details
POSTGRES_HOST=$(terraform output -raw postgresql_fqdn)
POSTGRES_DB="haystack"
POSTGRES_USER="psqladmin"
POSTGRES_PASSWORD="your-password-from-tfvars"

# Option 1: Using Azure CLI
az postgres flexible-server execute \
  --name $(echo $POSTGRES_HOST | cut -d. -f1) \
  --admin-user $POSTGRES_USER \
  --admin-password "$POSTGRES_PASSWORD" \
  --database-name $POSTGRES_DB \
  --file-path schema.sql

# Option 2: Using psql (if installed)
PGPASSWORD="$POSTGRES_PASSWORD" psql \
  -h $POSTGRES_HOST \
  -U $POSTGRES_USER \
  -d $POSTGRES_DB \
  -f schema.sql
```

## Step 7: Deploy Cohere Model (if needed)

If using Azure AI Foundry for Cohere (not cloud API):

1. Go to [Azure AI Studio](https://ai.azure.com/)
2. Find the Cognitive Services resource created by Terraform
3. Navigate to "Model deployments"
4. Deploy "Cohere Rerank v3.5" with name: `cohere-rerank-v3`
5. Copy the API key and update Key Vault secret if needed:

```bash
# Get Key Vault name
KV_NAME=$(terraform output -raw key_vault_uri | cut -d/ -f3 | cut -d. -f1)

# Update Cohere API key in Key Vault
az keyvault secret set \
  --vault-name $KV_NAME \
  --name "cohere-api-key" \
  --value "your-cohere-api-key-from-ai-studio"
```

## Step 8: Access Services

Get service URLs:

```bash
# n8n URL
terraform output -raw n8n_fqdn_url

# Haystack URL
terraform output -raw haystack_fqdn_url
```

Test access:

```bash
# Test n8n (should return HTTP 200 or redirect)
curl -I $(terraform output -raw n8n_fqdn_url)

# Test Haystack (should return HTTP 200)
curl -I $(terraform output -raw haystack_fqdn_url)
```

## Step 9: Verify Deployment

Check all resources were created:

```bash
# List all resources in the resource group
az resource list \
  --resource-group $(terraform output -raw resource_group_name) \
  --output table
```

Expected resources:
- 1 Container Apps Environment
- 2 Container Apps (n8n, Haystack)
- 1 PostgreSQL Flexible Server
- 1 Storage Account
- 1 Key Vault
- 1 Cognitive Services account
- Supporting resources (identities, storage configs, etc.)

## Troubleshooting

### Container App Won't Start

Check logs:
```bash
az containerapp logs show \
  --name $(terraform output -json | jq -r '.n8n_fqdn_url.value' | cut -d. -f1) \
  --resource-group $(terraform output -raw resource_group_name) \
  --follow
```

### PostgreSQL Connection Failed

Check firewall rules:
```bash
az postgres flexible-server firewall-rule list \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw postgresql_fqdn | cut -d. -f1)
```

Add your IP if needed:
```bash
MY_IP=$(curl -s ifconfig.me)
az postgres flexible-server firewall-rule create \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw postgresql_fqdn | cut -d. -f1) \
  --rule-name "my-ip" \
  --start-ip-address $MY_IP \
  --end-ip-address $MY_IP
```

### Key Vault Access Denied

Ensure you have proper permissions:
```bash
KV_NAME=$(terraform output -raw key_vault_uri | cut -d/ -f3 | cut -d. -f1)
az keyvault set-policy \
  --name $KV_NAME \
  --upn your-email@domain.com \
  --secret-permissions get list
```

## Cleanup

To destroy all resources:

```bash
# Destroy infrastructure (be careful!)
terraform destroy -var-file=terraform.tfvars

# Remove backend storage (optional)
az group delete --name tfstate-rg --yes
```

## Next Steps

1. **Configure n8n**: Access n8n URL and set up workflows
2. **Test Haystack**: Send test documents to Haystack API
3. **Monitor Costs**: Check Azure Cost Management
4. **Enable Monitoring**: Add Application Insights if needed
5. **Backup Data**: Configure PostgreSQL backups

## Security Checklist

- [ ] Strong PostgreSQL password set
- [ ] IP whitelisting configured
- [ ] Key Vault access restricted
- [ ] Secrets never committed to Git
- [ ] Backend state encrypted
- [ ] Regular security updates planned

## Support

For issues or questions:
1. Check `README.md` for architecture details
2. Review `ARCHITECTURE_VERIFICATION.md` for requirements
3. Read `IMPLEMENTATION_SUMMARY.md` for design decisions
4. Open GitHub issue with details

---

**Estimated Deployment Time**: 15-20 minutes

**Estimated Monthly Cost**: ~$120-150 USD (development workload)
