# Group 3, the workload switch (deploy_workload). Offline: every provider is mocked and the
# Foundry module is replaced by its outputs.
mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_client_config" {
    defaults = {
      object_id       = "00000000-0000-0000-0000-000000000001"
      tenant_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }

  mock_resource "azurerm_resource_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12"
    }
  }

  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12/providers/Microsoft.OperationalInsights/workspaces/log-alz-dev-ab12"
    }
  }

  mock_resource "azurerm_key_vault" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12/providers/Microsoft.KeyVault/vaults/kv-alz-dev-ab12"
      vault_uri = "https://kv-alz-dev-ab12.vault.azure.net/"
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      principal_id = "00000000-0000-0000-0000-0000000000a1"
      client_id    = "00000000-0000-0000-0000-0000000000a2"
    }
  }

  mock_resource "azurerm_app_configuration" {
    defaults = {
      id       = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12/providers/Microsoft.AppConfiguration/configurationStores/appcs-alz-dev-ab12"
      endpoint = "https://appcs-alz-dev-ab12.azconfig.io"
    }
  }

  mock_resource "azurerm_container_registry" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12/providers/Microsoft.ContainerRegistry/registries/cralzdevab12"
    }
  }

  mock_resource "azurerm_container_app_environment" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12/providers/Microsoft.App/managedEnvironments/cae-alz-dev-ab12"
    }
  }

  mock_resource "azurerm_search_service" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12/providers/Microsoft.Search/searchServices/srch-alz-dev-app-ab12"
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12/providers/Microsoft.Storage/storageAccounts/stalzdevappab12"
    }
  }
}

mock_provider "random" {
  override_during = plan

  mock_resource "random_string" {
    defaults = {
      result = "ab12"
    }
  }
}

mock_provider "modtm" {
  override_during = plan
}

mock_provider "time" {
  override_during = plan
}

override_module {
  target = module.foundry
  outputs = {
    ai_foundry_name = "aif-alz-dev-ab12"
    ai_foundry_id   = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12/providers/Microsoft.CognitiveServices/accounts/aif-alz-dev-ab12"
  }
}

# A local terraform.tfvars is loaded by terraform test too: pin the inputs the runs depend on.
variables {
  project_user_principals           = {}
  allowed_ip_ranges                 = []
  deploy_agent_service_dependencies = true
  deploy_workload                   = true
  app_settings_writer_principals = {
    owner = {
      principal_id = "00000000-0000-0000-0000-0000000000b1"
    }
  }
}

run "workload_on" {
  command = plan

  assert {
    condition     = length(azurerm_app_configuration.this) == 1 && azurerm_app_configuration.this[0].local_auth_enabled == false && azurerm_app_configuration.this[0].public_network_access == "Enabled"
    error_message = "App Configuration is missing, accepts keys, or its public endpoint is off."
  }

  assert {
    condition     = azurerm_container_registry.this[0].admin_enabled == false && azurerm_container_registry.this[0].anonymous_pull_enabled == false
    error_message = "Container Registry has its admin user or anonymous pull on."
  }

  assert {
    condition     = azurerm_container_app_environment.this[0].logs_destination == "azure-monitor" && azurerm_monitor_diagnostic_setting.app_env[0].log_analytics_workspace_id == azurerm_log_analytics_workspace.this.id
    error_message = "Container Apps logs don't go to Log Analytics through a diagnostic setting."
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.app) == 1 && azurerm_user_assigned_identity.app[0].name == "id-alz-dev-app"
    error_message = "The applications' identity is missing or misnamed."
  }

  assert {
    condition     = alltrue([for k in ["app_config", "acr_pull", "foundry"] : contains(keys(azurerm_role_assignment.app_identity), k)])
    error_message = "The applications' identity can't read settings, pull images and call Foundry."
  }

  assert {
    condition     = endswith(azurerm_role_assignment.app_identity["app_config"].role_definition_id, "516239f1-63e1-4d78-a4de-a74fb236a071") && endswith(azurerm_role_assignment.app_identity["foundry"].scope, "/accounts/aif-alz-dev-ab12")
    error_message = "The applications' identity has the wrong App Configuration role or Foundry scope."
  }

  assert {
    condition     = length(azurerm_role_assignment.app_settings_writer) == 1 && azurerm_role_assignment.app_settings_writer["owner"].principal_id == "00000000-0000-0000-0000-0000000000b1" && endswith(azurerm_role_assignment.app_settings_writer["owner"].role_definition_id, "5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b")
    error_message = "The listed settings writers don't get App Configuration Data Owner."
  }

  assert {
    condition     = azurerm_app_configuration_key.settings["landingzone:foundry:project_endpoint"].value == "https://aif-alz-dev-ab12.services.ai.azure.com/api/projects/proj-alz-dev"
    error_message = "App Configuration does not hold the Foundry project endpoint."
  }

  assert {
    condition     = azurerm_app_configuration_key.settings["landingzone:foundry:models"].value == "gpt-5.4-mini" && azurerm_app_configuration_key.settings["landingzone:foundry:models"].label == "dev"
    error_message = "App Configuration does not hold the model names, labeled with the environment."
  }

  assert {
    condition     = contains(keys(azurerm_app_configuration_key.settings), "landingzone:app_data:search_endpoint") && azurerm_app_configuration_key.settings["landingzone:key_vault:uri"].value == "https://kv-alz-dev-ab12.vault.azure.net/"
    error_message = "App Configuration does not hold the application data endpoints or the Key Vault URI."
  }

  assert {
    condition     = length(local.names.key_vault) <= 24 && output.key_vault_name == "kv-alz-dev-ab12"
    error_message = "Key Vault name is longer than 24 characters, or not in the outputs."
  }

  assert {
    condition     = azurerm_key_vault.this[0].rbac_authorization_enabled == true && azurerm_key_vault.this[0].purge_protection_enabled == true
    error_message = "Key Vault is not on RBAC authorization with purge protection."
  }

  assert {
    condition     = azurerm_key_vault.this[0].network_acls[0].default_action == "Allow"
    error_message = "With no allowed_ip_ranges, Key Vault is not open to all networks."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.key_vault[0].log_analytics_workspace_id == azurerm_log_analytics_workspace.this.id
    error_message = "Key Vault diagnostics don't go to Log Analytics."
  }

  assert {
    condition     = azurerm_search_service.app[0].local_authentication_enabled == false && azurerm_storage_account.app[0].shared_access_key_enabled == false
    error_message = "The application data accepts key authentication."
  }

  assert {
    condition     = length(azurerm_storage_account.app[0].network_rules) == 0
    error_message = "With no allowed_ip_ranges, the applications' Storage has network rules."
  }

  assert {
    condition     = length(azurerm_role_assignment.app_search_index) == 1 && length(azurerm_role_assignment.app_blob_data) == 1
    error_message = "The applications' identity has no access to the application data."
  }

  assert {
    condition     = length(local.names.app_registry) <= 50 && length(local.names.app_storage) <= 24
    error_message = "A name is too long."
  }
}

run "workload_off" {
  command = plan

  variables {
    deploy_workload = false
  }

  assert {
    condition     = length(azurerm_app_configuration.this) == 0 && length(azurerm_container_registry.this) == 0 && length(azurerm_container_app_environment.this) == 0 && length(azurerm_user_assigned_identity.app) == 0
    error_message = "With the workload off, an application platform resource is still planned."
  }

  assert {
    condition     = length(azurerm_key_vault.this) == 0 && length(azurerm_monitor_diagnostic_setting.key_vault) == 0
    error_message = "With the workload off, Key Vault is still planned."
  }

  assert {
    condition     = length(azurerm_search_service.app) == 0 && length(azurerm_storage_account.app) == 0 && length(azurerm_role_assignment.app_search_index) == 0 && length(azurerm_role_assignment.app_blob_data) == 0
    error_message = "With the workload off, the application data is still planned."
  }

  assert {
    condition     = length(azurerm_app_configuration_key.settings) == 0 && length(azurerm_role_assignment.app_settings_writer) == 0
    error_message = "With the workload off, settings or their writers' roles are still planned."
  }

  assert {
    condition     = output.key_vault_name == null && output.app_configuration_endpoint == null && output.app_data == null
    error_message = "With the workload off, its outputs are not null."
  }

  assert {
    condition     = length(azurerm_search_service.agent) == 1
    error_message = "Turning the workload off also removed the Agent Service's AI Search."
  }
}

run "workload_on_without_agent_service_dependencies" {
  command = plan

  variables {
    deploy_agent_service_dependencies = false
  }

  assert {
    condition     = length(azurerm_app_configuration.this) == 1 && length(azurerm_search_service.app) == 1 && length(azurerm_search_service.agent) == 0
    error_message = "The workload depends on the Agent Service dependencies."
  }

  assert {
    condition     = azurerm_app_configuration_key.settings["landingzone:agent_service:setup"].value == "basic"
    error_message = "App Configuration does not say the Agent Service runs the basic setup."
  }
}

run "ip_rules" {
  command = plan

  variables {
    allowed_ip_ranges = ["203.0.113.0/24"]
  }

  assert {
    condition     = contains(azurerm_search_service.app[0].allowed_ips, "203.0.113.0/24") && azurerm_storage_account.app[0].network_rules[0].default_action == "Deny"
    error_message = "allowed_ip_ranges does not restrict the application data."
  }

  assert {
    condition     = azurerm_key_vault.this[0].network_acls[0].default_action == "Deny" && contains(azurerm_key_vault.this[0].network_acls[0].ip_rules, "203.0.113.0/24")
    error_message = "allowed_ip_ranges does not restrict Key Vault."
  }
}

# The two switches deploy_workload replaced fail the plan when a tfvars file still sets them.
run "removed_platform_switch" {
  command = plan

  variables {
    deploy_application_platform = true
  }

  expect_failures = [var.deploy_application_platform]
}

run "removed_data_switch" {
  command = plan

  variables {
    deploy_application_data = false
  }

  expect_failures = [var.deploy_application_data]
}
