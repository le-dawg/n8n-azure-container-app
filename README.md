# n8n-azure-container-app

This Terraform configuration deploys an **n8n** instance on **Azure Container Apps**, along with an **Azure OpenAI Service** instance configured with the **GPT-4o-mini** model. By leveraging Azure Container Apps, this setup provides a cost-effective alternative to deploying n8n on Azure Kubernetes Service (AKS), as described on the n8n [website](https://docs.n8n.io/hosting/installation/server-setups/azure/). Azure Container Apps simplify the deployment process while maintaining scalability and reducing operational overhead.
 
### Key Features:
- **n8n Workflow Automation**: Deploys n8n, a powerful workflow automation tool, in a highly available and scalable environment using Azure Container Apps.
- **Optional Azure MCP Server Container**: Optionally deploys an additional container app integrated with MCP/Azure, providing Azure-specific context to the agent in n8n. This container app includes an NGINX instance configured as a reverse proxy to the MCP server, ensuring seamless communication and enhanced functionality.
- **Azure OpenAI Integration**: Provisions an Azure OpenAI Service instance with the GPT-4o-mini model, enabling advanced AI capabilities for your workflows.
- **Cost Optimization**: Utilizes Azure Container Apps to minimize costs compared to AKS, making it an ideal choice for small to medium-scale deployments.
- **Secure Configuration**: Integrates with Azure Key Vault to securely manage sensitive information, such as API keys and secrets.
- **Customizable Deployment**: Supports flexible configuration options for region, tags, and telemetry, allowing you to tailor the deployment to your specific needs.
- **Azure Verified Modules**: Leverages Azure Verified Modules (AVMs) to ensure the use of well-defined, tested, and Microsoft-supported modules, enhancing reliability and maintainability.

This repository was created to provide a more affordable and accessible way to host n8n in the Azure cloud, as the AKS-based solution was found to be expensive for smaller-scale use cases. This configuration offers a practical alternative, combining the power of n8n and Azure OpenAI with the cost-efficiency and simplicity of Azure Container Apps.

## Remote State Configuration

Terraform is configured to use the Azure Storage backend. Before the first `terraform init`, ensure your operator identity has the `Storage Blob Data Contributor` role on the deployment storage account.

1. Deploy or select the target resource group and subscription as usual, then run `terraform apply` once locally if you still need to create the storage account. This stack now provisions a private blob container named `tfstate` in the same account that stores n8n configuration files.
2. Initialize Terraform with backend settings that match your environment (replace the placeholders with the output values from a previous apply or with known names):
   ```bash
   terraform init \
     -backend-config="resource_group_name=<rg-name>" \
     -backend-config="storage_account_name=<storage-account-name>" \
     -backend-config="container_name=tfstate"
   ```
   The backend key defaults to `terraform.tfstate`, but you can override it with another `-backend-config` flag if you keep multiple environments in the same container.
3. When migrating an existing local state file, add `-migrate-state` to the `terraform init` command and ensure the local `terraform.tfstate` is present.

Once initialized, subsequent plans and applies will read and write state directly from Azure Storage.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4, < 5.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.7 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.26.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.7.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_container_app_mcp"></a> [container\_app\_mcp](#module\_container\_app\_mcp) | Azure/avm-res-app-containerapp/azurerm | 0.4.0 |
| <a name="module_container_app_n8n"></a> [container\_app\_n8n](#module\_container\_app\_n8n) | Azure/avm-res-app-containerapp/azurerm | 0.4.0 |
| <a name="module_key_vault"></a> [key\_vault](#module\_key\_vault) | Azure/avm-res-keyvault-vault/azurerm | 0.10.0 |
| <a name="module_naming"></a> [naming](#module\_naming) | Azure/naming/azurerm | 0.4.0 |
| <a name="module_openai"></a> [openai](#module\_openai) | Azure/avm-res-cognitiveservices-account/azurerm | 0.7.0 |
| <a name="module_postgresql"></a> [postgresql](#module\_postgresql) | Azure/avm-res-dbforpostgresql-flexibleserver/azurerm | 0.1.4 |
| <a name="module_storage"></a> [storage](#module\_storage) | Azure/avm-res-storage-storageaccount/azurerm | 0.5.0 |

## Resources

| Name | Type |
|------|------|
| [azurerm_container_app_environment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment) | resource |
| [azurerm_container_app_environment_storage.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app_environment_storage) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_user_assigned_identity.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [random_password.myadminpassword](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_deploy_mcp"></a> [deploy\_mcp](#input\_deploy\_mcp) | This variable controls whether or not the MCP container app is deployed.<br/>If it is set to true, then the MCP container app will be deployed. | `bool` | `false` | no |
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | This variable controls whether or not telemetry is enabled for the module.<br/>For more information see https://aka.ms/avm/telemetryinfo.<br/>If it is set to false, then no telemetry will be collected. | `bool` | `false` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region where the resource should be deployed.<br/>If null, the location will be inferred from the resource group location. | `string` | `"eastu2"` | no |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Azure Subscription ID | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Custom tags to apply to the resource. | `map(string)` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_mcp_endpoint_sse"></a> [mcp\_endpoint\_sse](#output\_mcp\_endpoint\_sse) | The sse endpoint of the MCP Server |
| <a name="output_n8n_fqdn_url"></a> [n8n\_fqdn\_url](#output\_n8n\_fqdn\_url) | https url that contains ingress's fqdn, could be used to access the n8n app. |
| <a name="output_openai_api_version"></a> [openai\_api\_version](#output\_openai\_api\_version) | The version of the OpenAI API to n8n credential. See https://learn.microsoft.com/en-us/azure/ai-services/openai/api-version-deprecation |
| <a name="output_openai_deployment_name"></a> [openai\_deployment\_name](#output\_openai\_deployment\_name) | The name of the OpenAI deployment. |
| <a name="output_openai_endpoint"></a> [openai\_endpoint](#output\_openai\_endpoint) | The endpoint of the OpenAI deployment. |
| <a name="output_openai_key_secret_url"></a> [openai\_key\_secret\_url](#output\_openai\_key\_secret\_url) | https url that contains the openai key secret in the key vault. |
| <a name="output_openai_resource_name"></a> [openai\_resource\_name](#output\_openai\_resource\_name) | The name of the OpenAI deployment. |
<!-- END_TF_DOCS -->
