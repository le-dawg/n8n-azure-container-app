# Azure Container App - Generic Module

This Terraform module provides a flexible, reusable configuration for deploying containerized applications on Azure Container Apps (ACA).

## Features

- 🐳 **Single or multi-container support** - Run one or multiple containers in a pod-like configuration
- 🔐 **Secrets management** - Integrate with Azure Key Vault or use direct values (dev only)
- 📦 **Volume mounts** - Support for Azure Files (persistent) and EmptyDir (temporary)
- 🌐 **Ingress configuration** - Expose apps publicly or internally with HTTPS
- 🔑 **Managed Identity** - System or user-assigned identities for Azure resource access
- 📊 **Health probes** - Liveness, readiness, and startup probes for container health
- 🔄 **Autoscaling** - Min/max replicas and custom scale rules
- 🎯 **Traffic splitting** - Support for blue/green deployments

## Usage

### Simple Web Application

```hcl
module "my_app" {
  source = "./modules/aca_app"

  name                         = "my-web-app"
  resource_group_name          = "my-rg"
  container_app_environment_id = azurerm_container_app_environment.this.id

  containers = [
    {
      name   = "web"
      image  = "nginx:latest"
      cpu    = 0.25
      memory = "0.5Gi"
      env = [
        { name = "PORT", value = "80" }
      ]
    }
  ]

  ingress = {
    external_enabled = true
    target_port      = 80
    traffic_weight = [
      { latest_revision = true, percentage = 100 }
    ]
  }

  tags = {
    environment = "dev"
    project     = "my-project"
  }
}
```

### Application with Persistent Storage

```hcl
module "stateful_app" {
  source = "./modules/aca_app"

  name                         = "stateful-app"
  resource_group_name          = "my-rg"
  container_app_environment_id = azurerm_container_app_environment.this.id

  containers = [
    {
      name   = "app"
      image  = "myapp:latest"
      cpu    = 0.5
      memory = "1Gi"
      volume_mounts = [
        {
          name = "data"
          path = "/data"
        }
      ]
    }
  ]

  volumes = [
    {
      name         = "data"
      storage_type = "AzureFile"
      storage_name = "myshare"  # Must be configured in Container App Environment
    }
  ]

  ingress = {
    external_enabled = false  # Internal only
    target_port      = 8080
    traffic_weight = [
      { latest_revision = true, percentage = 100 }
    ]
  }
}
```

### Application with Secrets from Key Vault

```hcl
module "secure_app" {
  source = "./modules/aca_app"

  name                         = "secure-app"
  resource_group_name          = "my-rg"
  container_app_environment_id = azurerm_container_app_environment.this.id

  containers = [
    {
      name   = "app"
      image  = "myapp:latest"
      cpu    = 0.25
      memory = "0.5Gi"
      env = [
        { name = "PUBLIC_VAR", value = "public-value" },
        { name = "DB_PASSWORD", secret_name = "db-password" },
        { name = "API_KEY", secret_name = "api-key" }
      ]
    }
  ]

  secrets = {
    db-password = {
      name                = "db-password"
      key_vault_secret_id = azurerm_key_vault_secret.db_password.id
      identity            = azurerm_user_assigned_identity.this.id
    }
    api-key = {
      name                = "api-key"
      key_vault_secret_id = azurerm_key_vault_secret.api_key.id
      identity            = azurerm_user_assigned_identity.this.id
    }
  }

  managed_identities = {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.this.id]
  }

  ingress = {
    external_enabled = true
    target_port      = 8080
    traffic_weight = [
      { latest_revision = true, percentage = 100 }
    ]
  }
}
```

### Multi-Container Application (Sidecar Pattern)

```hcl
module "multi_container_app" {
  source = "./modules/aca_app"

  name                         = "app-with-proxy"
  resource_group_name          = "my-rg"
  container_app_environment_id = azurerm_container_app_environment.this.id

  containers = [
    {
      name   = "app"
      image  = "myapp:latest"
      cpu    = 0.5
      memory = "1Gi"
      env = [
        { name = "PORT", value = "5000" }
      ]
    },
    {
      name   = "nginx-proxy"
      image  = "nginx:latest"
      cpu    = 0.25
      memory = "0.5Gi"
      # Configure nginx to proxy to localhost:5000
      command = ["sh", "-c"]
      args = [
        <<-EOT
          cat > /etc/nginx/conf.d/default.conf <<'EOF'
          server {
            listen 80;
            location / {
              proxy_pass http://localhost:5000;
            }
          }
          EOF
          nginx -g 'daemon off;'
        EOT
      ]
    }
  ]

  ingress = {
    external_enabled = true
    target_port      = 80  # Nginx port
    traffic_weight = [
      { latest_revision = true, percentage = 100 }
    ]
  }
}
```

### Autoscaling Configuration

```hcl
module "scalable_app" {
  source = "./modules/aca_app"

  name                         = "scalable-app"
  resource_group_name          = "my-rg"
  container_app_environment_id = azurerm_container_app_environment.this.id

  min_replicas = 1
  max_replicas = 10

  containers = [
    {
      name   = "app"
      image  = "myapp:latest"
      cpu    = 0.5
      memory = "1Gi"
    }
  ]

  ingress = {
    external_enabled = true
    target_port      = 8080
    traffic_weight = [
      { latest_revision = true, percentage = 100 }
    ]
  }

  scale_rules = [
    {
      name = "http-rule"
      type = "http"
      metadata = {
        concurrentRequests = "10"
      }
    }
  ]
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.8, < 2.0 |
| azurerm | ~> 4.5 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.5 |

## Inputs

See [variables.tf](./variables.tf) for detailed input descriptions.

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Container App name | `string` | n/a | yes |
| resource_group_name | Resource group name | `string` | n/a | yes |
| container_app_environment_id | Container App Environment ID | `string` | n/a | yes |
| containers | Container configurations | `list(object)` | n/a | yes |
| init_containers | Init container configurations | `list(object)` | `[]` | no |
| volumes | Volume configurations | `list(object)` | `[]` | no |
| min_replicas | Minimum replicas | `number` | `1` | no |
| max_replicas | Maximum replicas | `number` | `1` | no |
| ingress | Ingress configuration | `object` | `null` | no |
| secrets | Secret configurations | `map(object)` | `{}` | no |
| managed_identities | Managed identity configuration | `object` | `null` | no |
| scale_rules | Autoscaling rules | `list(object)` | `null` | no |
| revision_mode | Revision mode | `string` | `"Single"` | no |
| enable_telemetry | Enable Azure telemetry | `bool` | `false` | no |
| tags | Resource tags | `map(string)` | `{}` | no |

## Outputs

See [outputs.tf](./outputs.tf) for detailed output descriptions.

| Name | Description |
|------|-------------|
| id | Container App resource ID |
| name | Container App name |
| fqdn | Fully qualified domain name |
| fqdn_url | HTTPS URL |
| latest_revision_name | Latest revision name |
| outbound_ip_addresses | Outbound IP addresses |
| identity | Managed identity details |

## Best Practices

### 1. Resource Sizing

**Development**:
```hcl
cpu    = 0.25
memory = "0.5Gi"
```

**Production**:
```hcl
cpu    = 1.0
memory = "2Gi"
```

### 2. Health Probes

Always configure health probes for production:

```hcl
readiness_probe = {
  path                    = "/health/ready"
  port                    = 8080
  transport               = "HTTP"
  initial_delay_seconds   = 5
  period_seconds          = 10
  failure_threshold       = 3
}

liveness_probe = {
  path                    = "/health/live"
  port                    = 8080
  transport               = "HTTP"
  initial_delay_seconds   = 30
  period_seconds          = 30
  failure_threshold       = 3
}
```

### 3. Secrets Management

**Development** (acceptable for dev/test only):
```hcl
secrets = {
  my-secret = {
    name  = "my-secret"
    value = "dev-value-only"
  }
}
```

**Production** (always use Key Vault):
```hcl
secrets = {
  my-secret = {
    name                = "my-secret"
    key_vault_secret_id = azurerm_key_vault_secret.my_secret.id
    identity            = azurerm_user_assigned_identity.this.id
  }
}
```

### 4. Ingress Security

**Public applications**:
```hcl
ingress = {
  external_enabled           = true
  allow_insecure_connections = false  # Always require HTTPS
  target_port                = 8080
}
```

**Internal applications**:
```hcl
ingress = {
  external_enabled = false
  target_port      = 8080
}
```

### 5. Autoscaling

For production workloads with variable load:
```hcl
min_replicas = 2    # Avoid cold starts
max_replicas = 10   # Limit cost

scale_rules = [
  {
    name = "http-rule"
    type = "http"
    metadata = {
      concurrentRequests = "10"
    }
  }
]
```

For cost-sensitive dev environments:
```hcl
min_replicas = 0  # Scale to zero when idle
max_replicas = 3
```

## Common Patterns

### Pattern 1: Stateless Web API
- No volumes
- External ingress
- Autoscaling enabled
- Health probes configured

### Pattern 2: Background Worker
- No ingress
- Queue-based scaling
- Managed identity for queue access

### Pattern 3: Database-backed Application
- Secrets from Key Vault for DB credentials
- External ingress
- Readiness probe checks DB connection
- Managed identity for additional Azure resources

### Pattern 4: Multi-tenant Service
- Multiple revisions (traffic splitting)
- Custom domain per tenant
- Isolated configuration per revision

## Troubleshooting

### Container fails to start

1. Check container logs:
   ```bash
   az containerapp logs show --name <name> --resource-group <rg>
   ```

2. Verify image exists and is accessible
3. Check resource limits (CPU/memory)
4. Verify environment variables and secrets

### Ingress not accessible

1. Verify `external_enabled = true` for internet access
2. Check target_port matches container's listening port
3. Verify firewall rules if using custom networking
4. Check Container App Environment networking configuration

### Autoscaling not working

1. Verify min_replicas < max_replicas
2. Check scale rules are correctly configured
3. Monitor metrics to ensure thresholds are reached
4. Verify Container App Environment has sufficient capacity

## Related Resources

- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Container Apps Scaling](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
- [Container Apps Secrets](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets)

## License

This module is part of the n8n-azure-container-app repository.
