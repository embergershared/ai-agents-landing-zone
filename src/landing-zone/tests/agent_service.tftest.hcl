# The Agent Service dependencies switch: on, off, and with an existing dependency set.
# Offline: every provider is mocked and the Foundry module is replaced by its outputs; the
# module inputs are checked through the locals that main.foundry.tf passes to it.
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
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12/providers/Microsoft.KeyVault/vaults/kv-alz-dev-ab12"
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
  project_user_principals             = {}
  allowed_ip_ranges                   = []
  deploy_agent_service_dependencies   = true
  existing_agent_service_dependencies = null
}

run "switch_on_creates_the_dependencies" {
  command = plan

  assert {
    condition     = local.agent_deps_create == true && local.foundry_account.create_ai_agent_service == true && local.foundry_projects.main.create_project_connections == true
    error_message = "With the switch on, create_byor, create_ai_agent_service and create_project_connections are not all true."
  }

  assert {
    condition     = alltrue([for d in [local.agent_cosmos_db_definition, local.agent_search_definition, local.agent_storage_definition] : length(d) == 1 && contains(keys(d), "agent")])
    error_message = "With the switch on, Cosmos DB, AI Search and Storage are not all defined."
  }

  assert {
    condition     = local.foundry_projects.main.cosmos_db_connection.new_resource_map_key == "agent" && local.foundry_projects.main.ai_search_connection.new_resource_map_key == "agent" && local.foundry_projects.main.storage_account_connection.new_resource_map_key == "agent"
    error_message = "The project does not connect to the new dependency set."
  }

  assert {
    condition     = alltrue([for c in local.agent_cosmos_db_definition["agent"].diagnostic_settings["to_log_analytics"].metric_categories : contains(["SLI", "Requests"], c)])
    error_message = "Cosmos DB diagnostics use a metric category it doesn't accept (only SLI and Requests)."
  }

  assert {
    condition     = local.agent_cosmos_db_definition["agent"].capabilities[0].name == "EnableServerless"
    error_message = "Cosmos DB is not serverless by default."
  }

  assert {
    condition     = local.agent_cosmos_db_definition["agent"].local_authentication_disabled == true && local.agent_search_definition["agent"].local_authentication_enabled == false && local.agent_storage_definition["agent"].shared_access_key_enabled == false
    error_message = "A dependency accepts key authentication."
  }

  assert {
    condition     = local.agent_cosmos_db_definition["agent"].public_network_access_enabled && local.agent_search_definition["agent"].public_network_access_enabled && local.agent_storage_definition["agent"].public_network_access_enabled
    error_message = "A dependency's public endpoint is off."
  }

  assert {
    condition     = length(local.agent_cosmos_db_definition["agent"].ip_range_filter) == 0 && local.agent_storage_definition["agent"].network_rules == null
    error_message = "With no allowed_ip_ranges, Cosmos DB or Storage restricts networks."
  }

  assert {
    condition     = local.agent_storage_definition["agent"].name == "stalzdevagentab12" && length(local.agent_storage_definition["agent"].name) <= 24
    error_message = "The Agent Service storage account name is wrong or too long."
  }

  assert {
    condition     = output.agent_service_setup == "standard" && output.agent_service_dependencies.cosmos_db_name == "cosmos-alz-dev-ab12"
    error_message = "The outputs don't report the standard setup with the new dependencies."
  }
}

run "switch_off_uses_the_basic_setup" {
  command = plan

  variables {
    deploy_agent_service_dependencies = false
  }

  assert {
    condition     = local.agent_deps_create == false && local.foundry_account.create_ai_agent_service == false && local.foundry_projects.main.create_project_connections == false
    error_message = "With the switch off, create_byor, create_ai_agent_service and create_project_connections are not all false."
  }

  assert {
    condition     = length(local.agent_cosmos_db_definition) == 0 && length(local.agent_search_definition) == 0 && length(local.agent_storage_definition) == 0
    error_message = "With the switch off, a dependency is still defined."
  }

  assert {
    condition     = length(local.foundry_projects.main.cosmos_db_connection) == 0 && length(local.foundry_projects.main.ai_search_connection) == 0 && length(local.foundry_projects.main.storage_account_connection) == 0
    error_message = "With the switch off, the project still has connections."
  }

  assert {
    condition     = output.agent_service_setup == "basic" && output.agent_service_dependencies == null
    error_message = "The outputs don't report the basic setup."
  }
}

run "switch_on_with_existing_dependencies" {
  command = plan

  variables {
    existing_agent_service_dependencies = {
      cosmos_db_resource_id       = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-shared/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-shared"
      ai_search_resource_id       = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-shared/providers/Microsoft.Search/searchServices/srch-shared"
      storage_account_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-shared/providers/Microsoft.Storage/storageAccounts/stshared"
    }
  }

  assert {
    condition     = local.agent_deps_create == false && local.agent_deps_existing == true && local.foundry_account.create_ai_agent_service == true && local.foundry_projects.main.create_project_connections == true
    error_message = "With existing dependencies, nothing should be created but the Agent Service and connections should be."
  }

  assert {
    condition     = length(local.agent_cosmos_db_definition) == 0 && length(local.agent_search_definition) == 0 && length(local.agent_storage_definition) == 0
    error_message = "With existing dependencies, a new dependency is still defined."
  }

  assert {
    condition     = endswith(local.foundry_projects.main.cosmos_db_connection.existing_resource_id, "/cosmos-shared") && endswith(local.foundry_projects.main.ai_search_connection.existing_resource_id, "/srch-shared") && endswith(local.foundry_projects.main.storage_account_connection.existing_resource_id, "/stshared")
    error_message = "The project does not connect to the existing dependencies."
  }

  assert {
    condition     = output.agent_service_setup == "standard (existing dependencies)" && output.agent_service_dependencies.storage_account_name == "stshared"
    error_message = "The outputs don't report the existing dependencies."
  }
}

run "provisioned_cosmos_db_and_ip_rules" {
  command = plan

  variables {
    agent_cosmos_db_serverless             = false
    agent_cosmos_db_total_throughput_limit = 4000
    allowed_ip_ranges                      = ["203.0.113.0/24"]
  }

  assert {
    condition     = length(local.agent_cosmos_db_definition["agent"].capabilities) == 0 && local.agent_cosmos_db_definition["agent"].capacity.total_throughput_limit == 4000
    error_message = "Provisioned mode does not use the throughput limit."
  }

  assert {
    condition     = contains(local.agent_cosmos_db_definition["agent"].ip_range_filter, "203.0.113.0/24") && contains(local.agent_cosmos_db_definition["agent"].ip_range_filter, "0.0.0.0")
    error_message = "Cosmos DB does not allow the listed ranges and Azure datacenters."
  }

  assert {
    condition     = local.agent_storage_definition["agent"].network_rules.default_action == "Deny" && local.agent_search_definition["agent"].network_rule_set.bypass == "AzureServices"
    error_message = "allowed_ip_ranges does not restrict Storage and AI Search."
  }
}

run "too_little_cosmos_db_throughput" {
  command = plan

  variables {
    agent_cosmos_db_serverless             = false
    agent_cosmos_db_total_throughput_limit = 1000
  }

  expect_failures = [var.agent_cosmos_db_total_throughput_limit]
}
