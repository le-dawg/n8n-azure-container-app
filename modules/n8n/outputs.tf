# ============================================================================
# n8n Module - Outputs
# ============================================================================

output "id" {
  description = "Resource ID of the n8n Container App."
  value       = module.n8n_container_app.id
}

output "name" {
  description = "Name of the n8n Container App."
  value       = module.n8n_container_app.name
}

output "fqdn" {
  description = "Fully qualified domain name of the n8n instance."
  value       = module.n8n_container_app.fqdn
}

output "fqdn_url" {
  description = "HTTPS URL to access the n8n web interface."
  value       = module.n8n_container_app.fqdn_url
}

output "webhook_url" {
  description = "Webhook URL configured for n8n workflows."
  value       = var.webhook_url != null ? var.webhook_url : "https://${var.name}.${var.aca_environment_default_domain}"
}

output "latest_revision_name" {
  description = "Name of the latest active revision."
  value       = module.n8n_container_app.latest_revision_name
}

output "outbound_ip_addresses" {
  description = "List of outbound IP addresses (for firewall allowlisting)."
  value       = module.n8n_container_app.outbound_ip_addresses
}

output "identity_principal_id" {
  description = "Principal ID of the managed identity."
  value       = module.n8n_container_app.identity.principal_id
}
