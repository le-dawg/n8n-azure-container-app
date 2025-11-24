# ============================================================================
# Azure Container App Module - Outputs
# ============================================================================

output "id" {
  description = "Resource ID of the Container App."
  value       = module.container_app.resource_id
}

output "name" {
  description = "Name of the Container App."
  value       = module.container_app.name
}

output "fqdn" {
  description = "Fully qualified domain name of the Container App (if ingress is enabled)."
  value       = try(module.container_app.fqdn, null)
}

output "fqdn_url" {
  description = "HTTPS URL of the Container App (if ingress is enabled)."
  value       = try(module.container_app.fqdn_url, null)
}

output "latest_revision_name" {
  description = "Name of the latest active revision."
  value       = try(module.container_app.resource.latest_revision_name, null)
}

output "latest_revision_fqdn" {
  description = "FQDN of the latest active revision."
  value       = try(module.container_app.resource.latest_revision_fqdn, null)
}

output "outbound_ip_addresses" {
  description = "List of outbound IP addresses for the Container App (for firewall allow-listing)."
  value       = try(module.container_app.resource.outbound_ip_addresses, [])
}

output "identity" {
  description = "Managed identity details (principal_id, tenant_id)."
  value = {
    principal_id = try(module.container_app.resource.identity[0].principal_id, null)
    tenant_id    = try(module.container_app.resource.identity[0].tenant_id, null)
    type         = try(module.container_app.resource.identity[0].type, null)
  }
}

output "resource" {
  description = "Full Container App resource object (for advanced use cases)."
  value       = module.container_app.resource
  sensitive   = true  # May contain sensitive configuration
}
