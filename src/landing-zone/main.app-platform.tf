# Application platform (deploy_application_platform): App Configuration holding the landing
# zone's endpoints and names, a Container Registry, a Container Apps environment, and the
# user-assigned identity applications run as. Entra ID only: no keys, no admin user.
locals {
  app_platform = var.deploy_application_platform
  app_data     = var.deploy_application_data

  # Subscription-scoped role definition IDs: the form Azure returns, so plans stay clean.
  role_ids = { for k, v in local.roles : k => "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${v}" }

  # Settings applications read from App Configuration, labeled with the environment.
  app_settings = merge(
    {
      "landingzone:foundry:openai_endpoint"  = "https://${module.foundry.ai_foundry_name}.openai.azure.com/"
      "landingzone:foundry:project_endpoint" = "https://${module.foundry.ai_foundry_name}.services.ai.azure.com/api/projects/${local.names.project}"
      "landingzone:foundry:models"           = join(",", keys(var.model_deployments))
      "landingzone:agent_service:setup"      = local.agent_service_enabled ? "standard" : "basic"
      "landingzone:key_vault:uri"            = azurerm_key_vault.this.vault_uri
      "landingzone:app_insights:connection"  = azurerm_application_insights.this.connection_string
    },
    local.app_data ? {
      "landingzone:app_data:search_endpoint" = "https://${local.names.app_search}.search.windows.net"
      "landingzone:app_data:blob_endpoint"   = "https://${local.names.app_storage}.blob.core.windows.net/"
    } : {}
  )
}

resource "azurerm_user_assigned_identity" "app" {
  count = local.app_platform ? 1 : 0

  name                = local.names.app_identity
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

resource "azurerm_app_configuration" "this" {
  count = local.app_platform ? 1 : 0

  name                     = local.names.app_config
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  sku                      = var.app_configuration_sku
  local_auth_enabled       = false
  public_network_access    = "Enabled"
  purge_protection_enabled = false
  tags                     = local.tags
}

# Whoever runs Terraform reads and writes the settings through the data plane (Entra ID only),
# even in a plan, so the role can't depend on who runs it: the pipeline identity gets it from
# src/state-backend, people running Terraform from a workstation get it here.
resource "azurerm_role_assignment" "app_settings_writer" {
  for_each = local.app_platform ? var.app_settings_writer_principals : {}

  scope              = azurerm_app_configuration.this[0].id
  role_definition_id = local.role_ids.app_configuration_data_owner
  principal_id       = each.value.principal_id
  principal_type     = each.value.principal_type
}

# The role used to go to the identity running Terraform; keep that assignment as "owner".
moved {
  from = azurerm_role_assignment.app_config_data_owner_deployer[0]
  to   = azurerm_role_assignment.app_settings_writer["owner"]
}

# Role assignments take a while to reach the data plane.
resource "time_sleep" "app_config_rbac" {
  count = local.app_platform ? 1 : 0

  create_duration = "60s"
  depends_on      = [azurerm_role_assignment.app_settings_writer]
}

resource "azurerm_app_configuration_key" "settings" {
  for_each = local.app_platform ? nonsensitive(toset(keys(local.app_settings))) : toset([])

  configuration_store_id = azurerm_app_configuration.this[0].id
  key                    = each.value
  label                  = var.environment
  value                  = local.app_settings[each.value]

  depends_on = [time_sleep.app_config_rbac]
}

resource "azurerm_monitor_diagnostic_setting" "app_config" {
  count = local.app_platform ? 1 : 0

  name                       = "to-log-analytics"
  target_resource_id         = azurerm_app_configuration.this[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_container_registry" "this" {
  count = local.app_platform ? 1 : 0

  name                          = local.names.app_registry
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  sku                           = var.container_registry_sku
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = true
  tags                          = local.tags
}

resource "azurerm_container_app_environment" "this" {
  count = local.app_platform ? 1 : 0

  name                = local.names.app_env
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  # Logs through a diagnostic setting (Entra ID), not the workspace's shared key: Log Analytics
  # has key authentication off.
  logs_destination = "azure-monitor"
  tags             = local.tags

  # Azure adds this profile anyway; declaring it keeps plans clean.
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_monitor_diagnostic_setting" "app_env" {
  count = local.app_platform ? 1 : 0

  name                       = "to-log-analytics"
  target_resource_id         = azurerm_container_app_environment.this[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# What the applications' identity may do: read settings, pull images, call Foundry.
resource "azurerm_role_assignment" "app_identity" {
  for_each = local.app_platform ? {
    app_config = { scope = azurerm_app_configuration.this[0].id, role = local.role_ids.app_configuration_data_reader }
    acr_pull   = { scope = azurerm_container_registry.this[0].id, role = local.role_ids.acr_pull }
    foundry    = { scope = module.foundry.ai_foundry_id, role = local.role_ids.foundry_user }
  } : {}

  scope              = each.value.scope
  role_definition_id = each.value.role
  principal_id       = azurerm_user_assigned_identity.app[0].principal_id
  principal_type     = "ServicePrincipal"
}
