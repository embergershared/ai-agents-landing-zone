output "resource_group_name" {
  description = "Resource group of the landing zone."
  value       = azurerm_resource_group.this.name
}

output "foundry_name" {
  description = "Foundry (AI Services) account name."
  value       = module.foundry.ai_foundry_name
}

output "foundry_openai_endpoint" {
  description = "OpenAI-compatible endpoint of the Foundry account (Entra ID tokens only)."
  value       = "https://${module.foundry.ai_foundry_name}.openai.azure.com/"
}

output "foundry_project_endpoint" {
  description = "Endpoint of the Foundry project, for the Foundry SDKs and the Agent Service."
  value       = "https://${module.foundry.ai_foundry_name}.services.ai.azure.com/api/projects/${local.names.project}"
}

output "model_deployment_names" {
  description = "Model deployment names, as applications pass them in the model parameter."
  value       = keys(var.model_deployments)
}

output "key_vault_name" {
  description = "Key Vault of the landing zone (RBAC authorization)."
  value       = azurerm_key_vault.this.name
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace that receives the diagnostics."
  value       = azurerm_log_analytics_workspace.this.id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (an identifier, not a key: local authentication is off)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}
