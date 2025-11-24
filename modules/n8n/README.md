# n8n Container App Module

This module deploys **n8n** (workflow automation platform) as an Azure Container App with persistent storage and PostgreSQL backend.

## Features

- 🔄 **Workflow Automation**: Deploy n8n for low-code workflow automation
- 💾 **Persistent Storage**: Azure Files mount for workflow and credential storage
- 🐘 **PostgreSQL Backend**: External PostgreSQL database for metadata
- 🔑 **Managed Identity**: Azure AD authentication for accessing Azure resources
- 🌐 **HTTPS Ingress**: Public or internal access with automatic TLS
- 🏥 **Health Probes**: Automatic restart on failure
- 📦 **Configurable Resources**: CPU, memory, and replica scaling

## Usage

### Basic Deployment

```hcl
module "n8n" {
  source = "./modules/n8n"

  name                         = "n8n-dev"
  resource_group_name          = "my-rg"
  container_app_environment_id = azurerm_container_app_environment.this.id

  # PostgreSQL Configuration
  postgres_host                = "mydb.postgres.database.azure.com"
  postgres_user                = "psqladmin"
  postgres_database            = "n8n"
  postgres_password_secret_id  = azurerm_key_vault_secret.db_password.id

  # Managed Identity
  managed_identity_id        = azurerm_user_assigned_identity.this.id
  managed_identity_client_id = azurerm_user_assigned_identity.this.client_id
  azure_tenant_id            = data.azurerm_client_config.current.tenant_id

  # Container App Environment
  aca_environment_default_domain = azurerm_container_app_environment.this.default_domain

  tags = {
    environment = "dev"
    application = "n8n"
  }
}
```

### Production Deployment with Basic Auth

```hcl
module "n8n_prod" {
  source = "./modules/n8n"

  name                         = "n8n-prod"
  resource_group_name          = "my-rg-prod"
  container_app_environment_id = azurerm_container_app_environment.prod.id

  # Resource Sizing for Production
  cpu          = 1.0
  memory       = "2Gi"
  min_replicas = 1  # Single instance for n8n
  max_replicas = 1

  # PostgreSQL Configuration
  postgres_host                = module.postgres.fqdn
  postgres_user                = "psqladmin"
  postgres_database            = "n8n"
  postgres_password_secret_id  = azurerm_key_vault_secret.db_password.id

  # Managed Identity
  managed_identity_id        = azurerm_user_assigned_identity.prod.id
  managed_identity_client_id = azurerm_user_assigned_identity.prod.client_id
  azure_tenant_id            = data.azurerm_client_config.current.tenant_id

  # Container App Environment
  aca_environment_default_domain = azurerm_container_app_environment.prod.default_domain

  # Enable Basic Authentication
  additional_env_vars = [
    {
      name  = "N8N_BASIC_AUTH_ACTIVE"
      value = "true"
    },
    {
      name  = "N8N_BASIC_AUTH_USER"
      value = "admin"
    },
    {
      name        = "N8N_BASIC_AUTH_PASSWORD"
      secret_name = "n8n-auth-password"
    },
    {
      name        = "N8N_ENCRYPTION_KEY"
      secret_name = "n8n-encryption-key"
    },
    {
      name  = "GENERIC_TIMEZONE"
      value = "Europe/Oslo"
    }
  ]

  # Note: You need to add the secrets to the module's secrets map
  # This requires extending the module or using the underlying aca_app module directly

  tags = {
    environment = "prod"
    application = "n8n"
  }
}
```

### Custom Domain

```hcl
module "n8n_custom_domain" {
  source = "./modules/n8n"

  name                         = "n8n"
  resource_group_name          = "my-rg"
  container_app_environment_id = azurerm_container_app_environment.this.id

  # Override webhook URL with custom domain
  webhook_url = "https://workflows.mycompany.com"

  # ... other configuration ...
}

# Configure custom domain on Container App after deployment
# (requires DNS CNAME and certificate)
```

## Prerequisites

### 1. Container App Environment

```hcl
resource "azurerm_container_app_environment" "this" {
  location            = "northeurope"
  name                = "my-aca-env"
  resource_group_name = azurerm_resource_group.this.name
}
```

### 2. Azure Files Storage

```hcl
resource "azurerm_container_app_environment_storage" "n8n" {
  name                         = "n8nconfig"
  container_app_environment_id = azurerm_container_app_environment.this.id
  account_name                 = azurerm_storage_account.this.name
  share_name                   = azurerm_storage_share.n8n.name
  access_key                   = azurerm_storage_account.this.primary_access_key
  access_mode                  = "ReadWrite"
}
```

### 3. PostgreSQL Database

```hcl
module "postgres" {
  source = "./modules/postgres_flexible"

  name                = "mydb"
  resource_group_name = azurerm_resource_group.this.name
  location            = "northeurope"

  administrator_login    = "psqladmin"
  administrator_password = random_password.postgres.result

  databases = {
    n8n = {
      name      = "n8n"
      charset   = "UTF8"
      collation = "en_US.utf8"
    }
  }

  # ... other configuration ...
}
```

### 4. Managed Identity

```hcl
resource "azurerm_user_assigned_identity" "this" {
  location            = azurerm_resource_group.this.location
  name                = "n8n-identity"
  resource_group_name = azurerm_resource_group.this.name
}
```

### 5. Key Vault Secret for DB Password

```hcl
resource "azurerm_key_vault_secret" "db_password" {
  name         = "n8n-db-password"
  value        = random_password.postgres.result
  key_vault_id = azurerm_key_vault.this.id
}
```

## Configuration

### Environment Variables

n8n supports many environment variables. Common ones are pre-configured, but you can add more via `additional_env_vars`:

```hcl
additional_env_vars = [
  # Basic Authentication
  { name = "N8N_BASIC_AUTH_ACTIVE", value = "true" },
  { name = "N8N_BASIC_AUTH_USER", value = "admin" },
  { name = "N8N_BASIC_AUTH_PASSWORD", secret_name = "n8n-auth-password" },
  
  # Encryption
  { name = "N8N_ENCRYPTION_KEY", secret_name = "n8n-encryption-key" },
  
  # Timezone
  { name = "GENERIC_TIMEZONE", value = "Europe/Oslo" },
  
  # Logging
  { name = "N8N_LOG_LEVEL", value = "info" },
  
  # Execution
  { name = "EXECUTIONS_PROCESS", value = "main" },
  { name = "EXECUTIONS_MODE", value = "regular" },
  
  # External Hooks (for observability)
  { name = "N8N_EXTERNAL_HOOK_FILES", value = "/data/external-hooks" },
]
```

See [n8n Environment Variables Documentation](https://docs.n8n.io/hosting/configuration/environment-variables/) for complete list.

### Persistence

By default, persistence is enabled via Azure Files. This stores:
- Workflow definitions
- Credentials (encrypted)
- Settings and preferences
- Execution history (if configured)

To disable (not recommended):

```hcl
enable_persistence = false
```

### Resource Sizing

| Workload | CPU | Memory | Description |
|----------|-----|--------|-------------|
| Dev/Test | 0.25 | 0.5Gi | Small workflows, occasional use |
| Small Prod | 0.5 | 1Gi | ≤10 active workflows |
| Medium Prod | 1.0 | 2Gi | 10-50 workflows, moderate frequency |
| Large Prod | 2.0 | 4Gi | 50+ workflows, high frequency |

```hcl
cpu    = 1.0
memory = "2Gi"
```

### Scaling

**Important**: n8n is primarily a single-instance application. While you can run multiple replicas, you need to configure queue mode:

```hcl
min_replicas = 1
max_replicas = 1  # Keep at 1 unless using queue mode

additional_env_vars = [
  # For multi-instance setup, enable queue mode
  { name = "EXECUTIONS_MODE", value = "queue" },
  { name = "QUEUE_BULL_REDIS_HOST", value = "redis-host" },
  { name = "QUEUE_BULL_REDIS_PORT", value = "6379" },
]
```

## Post-Deployment Configuration

### 1. Access n8n

```bash
# Get the URL
N8N_URL=$(terraform output -raw n8n_fqdn_url)

echo "n8n URL: $N8N_URL"

# Open in browser
open $N8N_URL  # macOS
xdg-open $N8N_URL  # Linux
start $N8N_URL  # Windows
```

### 2. Set Up Admin User

On first access, n8n will prompt you to create an admin user (unless basic auth is configured).

### 3. Configure Credentials

Add credentials in n8n UI:
- **Azure**: Use the managed identity (client ID output)
- **PostgreSQL**: For direct DB access (if needed)
- **OpenAI/Cohere**: For AI workflows
- **Other services**: As needed for your workflows

### 4. Configure Webhooks

Webhooks are automatically configured with the `webhook_url` output. Test with:

```bash
curl -X POST "$N8N_URL/webhook-test/test-webhook"
```

## Integration with Other Modules

### With RAG Functions

```hcl
# n8n can call RAG functions
module "n8n" {
  # ... configuration ...
  
  additional_env_vars = [
    {
      name  = "INGESTION_FUNCTION_URL"
      value = module.ingestion_function.function_url
    },
    {
      name  = "BM25_FUNCTION_URL"
      value = module.bm25_function.function_url
    },
    {
      name        = "INGESTION_FUNCTION_KEY"
      secret_name = "ingestion-function-key"
    },
    {
      name        = "BM25_FUNCTION_KEY"
      secret_name = "bm25-function-key"
    }
  ]
}
```

### With OpenAI

```hcl
module "n8n" {
  # ... configuration ...
  
  additional_env_vars = [
    {
      name  = "OPENAI_API_ENDPOINT"
      value = module.openai.endpoint
    },
    {
      name        = "OPENAI_API_KEY"
      secret_name = "openai-api-key"
    }
  ]
}
```

## Troubleshooting

### Issue: Cannot connect to PostgreSQL

**Solution**: Check firewall rules on PostgreSQL server:

```hcl
# Ensure firewall allows Container App
firewall_rules = {
  azure_services = {
    name             = "AllowAzureServices"
    start_ip_address = "0.0.0.0"
    end_ip_address   = "0.0.0.0"
  }
}
```

### Issue: Workflows not persisting

**Solution**: Verify Azure Files mount:

```bash
# Check storage configuration
az containerapp show \
  --name <n8n-name> \
  --resource-group <rg> \
  --query properties.template.volumes
```

### Issue: Cannot access n8n UI

**Solution**: Check ingress configuration:

```bash
# Verify ingress is enabled and external
az containerapp ingress show \
  --name <n8n-name> \
  --resource-group <rg>
```

### Issue: High memory usage

**Solution**: Increase memory or investigate workflows:

```hcl
memory = "2Gi"  # or higher
```

Also check for:
- Workflows with large data processing
- Memory leaks in custom code nodes
- Execution history retention settings

## Security Best Practices

1. **Enable Basic Auth or SSO**:
   ```hcl
   additional_env_vars = [
     { name = "N8N_BASIC_AUTH_ACTIVE", value = "true" },
     # Or configure SSO (SAML/OAuth)
   ]
   ```

2. **Use Encryption Key**:
   ```hcl
   additional_env_vars = [
     { name = "N8N_ENCRYPTION_KEY", secret_name = "n8n-encryption-key" }
   ]
   ```

3. **Restrict Ingress** (production):
   ```hcl
   ingress_external_enabled = false  # Internal only
   ```

4. **Regular Updates**:
   ```hcl
   n8n_image = "docker.io/n8nio/n8n:1.0.0"  # Pin version, update regularly
   ```

5. **Monitor Access Logs**:
   ```bash
   az monitor log-analytics query \
     --workspace <workspace-id> \
     --analytics-query "ContainerAppConsoleLogs_CL | where ContainerName_s == 'n8n'"
   ```

## Cost Optimization

- **Dev**: Use smallest resources (0.25 CPU, 0.5Gi RAM) ≈ $8/month
- **Prod**: Right-size based on workflow complexity (1.0 CPU, 2Gi RAM) ≈ $30/month
- **Scale to zero**: Not recommended for n8n (workflows need to be always running)

## Related Resources

- [n8n Documentation](https://docs.n8n.io/)
- [n8n Environment Variables](https://docs.n8n.io/hosting/configuration/environment-variables/)
- [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/)

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.8, < 2.0 |
| azurerm | ~> 4.5 |

## Inputs

See [variables.tf](./variables.tf) for complete documentation.

## Outputs

See [outputs.tf](./outputs.tf) for complete documentation.
