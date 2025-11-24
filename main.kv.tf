module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.0"

  location                      = azurerm_resource_group.this.location
  name                          = module.naming.key_vault.name_unique
  resource_group_name           = azurerm_resource_group.this.name
  enable_telemetry              = var.enable_telemetry
  public_network_access_enabled = true
  tags                          = var.tags
  tenant_id                     = data.azurerm_client_config.current.tenant_id

  secrets = {
    psqladmin-password = {
      name = "psqladmin-password"
    }
  }

  secrets_value = {
    psqladmin-password = random_password.myadminpassword.result
  }

  role_assignments = {
    deployment_user_kv_admin = {
      role_definition_id_or_name = "Key Vault Administrator"
      principal_id               = data.azurerm_client_config.current.object_id
    }
    container_app_kv_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = azurerm_user_assigned_identity.this.principal_id
    }
  }

  wait_for_rbac_before_secret_operations = {
    create = "60s"
  }

  network_acls = {
    bypass         = "AzureServices"
    default_action = "Allow"
  }
}
