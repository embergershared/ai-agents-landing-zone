# Foundry account, project and model deployments on public endpoints (no private endpoints),
# with key authentication off: callers use Entra ID tokens. The inputs are built as locals so
# that terraform test can check them without the module (its mocks lack ephemeral resources).
locals {
  foundry_account = {
    name                          = local.names.foundry
    disable_local_auth            = true
    create_ai_agent_service       = local.agent_service_enabled
    public_network_access_enabled = true
    network_acls = length(var.allowed_ip_ranges) == 0 ? null : {
      default_action = "Deny"
      bypass         = "AzureServices"
      ip_rules       = var.allowed_ip_ranges
    }
    role_assignments = {
      for key, p in var.project_user_principals : "foundry-user-${key}" => {
        role_definition_id_or_name = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.roles.foundry_user}"
        principal_id               = p.principal_id
        principal_type             = p.principal_type
      }
    }
  }

  foundry_projects = {
    main = merge({
      name                       = local.names.project
      display_name               = "Agent Landing Zone (${var.environment})"
      description                = "Foundry project of the Agent Landing Zone, ${var.environment} environment."
      create_project_connections = local.agent_service_enabled
    }, local.agent_project_connections)
  }

  foundry_model_deployments = {
    for name, d in var.model_deployments : name => {
      name = name
      model = {
        format  = "OpenAI"
        name    = d.model_name
        version = d.model_version
      }
      scale = {
        type     = d.sku
        capacity = d.capacity
      }
    }
  }
}

module "foundry" {
  source  = "Azure/avm-ptn-aiml-ai-foundry/azurerm"
  version = "0.12.0"

  base_name                  = var.name_prefix
  location                   = azurerm_resource_group.this.location
  resource_group_resource_id = azurerm_resource_group.this.id
  create_private_endpoints   = false
  create_byor                = local.agent_deps_create
  enable_telemetry           = var.enable_telemetry
  tags                       = local.tags

  resource_names = {
    ai_foundry_project              = local.names.project
    ai_foundry_project_display_name = local.foundry_projects.main.display_name
  }

  ai_foundry           = local.foundry_account
  ai_projects          = local.foundry_projects
  ai_model_deployments = local.foundry_model_deployments

  # Agent Service dependencies (main.agent-service.tf); empty maps when the switch is off.
  # AI Search: azurerm_search_service.agent, connected as an existing resource.
  cosmosdb_definition        = local.agent_cosmos_db_definition
  storage_account_definition = local.agent_storage_definition

  # Azure doesn't keep log_analytics_destination_type on a Foundry account, so every plan shows
  # it being set again (harmless; the module requires a value).
  diagnostic_settings = {
    to_log_analytics = {
      name                  = "to-log-analytics"
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
    }
  }
}
