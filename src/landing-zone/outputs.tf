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

output "agent_service_setup" {
  description = "Agent Service setup: standard (our Cosmos DB, AI Search and Storage, new or existing) or basic."
  value       = local.agent_service_enabled ? (local.agent_deps_existing ? "standard (existing dependencies)" : "standard") : "basic"
}

output "agent_service_dependencies" {
  description = "Cosmos DB, AI Search and Storage of the Agent Service, when the switch is on."
  value = local.agent_service_enabled ? {
    cosmos_db_name       = local.agent_deps_existing ? provider::azurerm::parse_resource_id(var.existing_agent_service_dependencies.cosmos_db_resource_id).resource_name : local.names.agent_cosmos
    ai_search_name       = local.agent_deps_existing ? provider::azurerm::parse_resource_id(var.existing_agent_service_dependencies.ai_search_resource_id).resource_name : local.names.agent_search
    storage_account_name = local.agent_deps_existing ? provider::azurerm::parse_resource_id(var.existing_agent_service_dependencies.storage_account_resource_id).resource_name : local.names.agent_storage
  } : null
}

output "app_configuration_endpoint" {
  description = "App Configuration endpoint; the settings are labeled with the environment."
  value       = local.app_platform ? azurerm_app_configuration.this[0].endpoint : null
}

output "app_identity" {
  description = "User-assigned identity the applications run as."
  value = local.app_platform ? {
    resource_id  = azurerm_user_assigned_identity.app[0].id
    client_id    = azurerm_user_assigned_identity.app[0].client_id
    principal_id = azurerm_user_assigned_identity.app[0].principal_id
  } : null
}

output "container_registry_login_server" {
  description = "Container Registry login server."
  value       = local.app_platform ? azurerm_container_registry.this[0].login_server : null
}

output "container_app_environment_id" {
  description = "Container Apps environment."
  value       = local.app_platform ? azurerm_container_app_environment.this[0].id : null
}

output "app_data" {
  description = "The applications' AI Search and Storage."
  value = local.app_data ? {
    search_name          = azurerm_search_service.app[0].name
    storage_account_name = azurerm_storage_account.app[0].name
  } : null
}
