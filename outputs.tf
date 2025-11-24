output "n8n_fqdn_url" {
  description = "https url that contains ingress's fqdn, could be used to access the n8n app."
  value       = module.container_app_n8n.fqdn_url
}

output "mcp_endpoint_sse" {
  description = "The sse endpoint of the MCP Server"
  value = try("${module.container_app_mcp[0].fqdn_url}/sse", null)
}

output "backend_storage_account_name" {
  description = "Storage account that hosts the Terraform remote state container."
  value       = module.storage.name
}

output "backend_storage_container_name" {
  description = "Storage container used for Terraform remote state."
  value       = azurerm_storage_container.tfstate.name
}

output "backend_resource_group_name" {
  description = "Resource group that contains the Terraform remote state storage."
  value       = azurerm_resource_group.this.name
}
