# Group 1, Foundry essentials, on its own: groups 2 and 3 are off unless a run says otherwise.
# Offline: every provider is mocked, nothing is created in Azure. override_during = plan makes
# the mocked values known at plan time, so the runs can stay plan-only.
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

# A local terraform.tfvars is loaded by terraform test too: pin the inputs the runs depend on.
variables {
  project_user_principals           = {}
  allowed_ip_ranges                 = []
  deploy_agent_service_dependencies = false
  deploy_workload                   = false
}

# The Foundry module is replaced by its outputs: its own tests cover it, and the mocks can't run
# its ephemeral resources. Its inputs are checked through the foundry_* locals.
override_module {
  target = module.foundry
  outputs = {
    ai_foundry_name = "aif-alz-dev-ab12"
    ai_foundry_id   = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12/providers/Microsoft.CognitiveServices/accounts/aif-alz-dev-ab12"
  }
}

run "defaults" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.name == "rg-alz-dev-ab12" && azurerm_resource_group.this.location == "swedencentral"
    error_message = "Resource group name or region is not the default."
  }

  assert {
    condition     = local.names.foundry == "aif-alz-dev-ab12" && local.names.project == "proj-alz-dev"
    error_message = "Foundry account or project name does not follow the naming convention."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.local_authentication_enabled == false && azurerm_application_insights.this.local_authentication_enabled == false
    error_message = "Log Analytics or Application Insights accepts key authentication."
  }

  assert {
    condition     = length(azurerm_key_vault.this) == 0 && length(azurerm_app_configuration.this) == 0 && length(azurerm_search_service.app) == 0 && output.key_vault_name == null
    error_message = "With the workload off, a workload resource is still planned."
  }

  assert {
    condition     = length(azurerm_search_service.agent) == 0 && output.agent_service_setup == "basic"
    error_message = "With the Agent Service dependencies off, their AI Search is still planned."
  }

  assert {
    condition     = length(output.model_deployment_names) == 1 && output.model_deployment_names[0] == "gpt-5.4-mini"
    error_message = "The default model deployment is not gpt-5.4-mini."
  }

  assert {
    condition     = local.foundry_model_deployments["gpt-5.4-mini"].model.version == "2026-03-17" && local.foundry_model_deployments["gpt-5.4-mini"].scale.type == "GlobalStandard" && local.foundry_model_deployments["gpt-5.4-mini"].scale.capacity == 10
    error_message = "The default deployment is not gpt-5.4-mini 2026-03-17, GlobalStandard, 10K TPM."
  }

  assert {
    condition     = local.foundry_account.disable_local_auth == true && local.foundry_account.public_network_access_enabled == true
    error_message = "Foundry accepts key authentication, or its public endpoint is off."
  }

  assert {
    condition     = local.foundry_account.network_acls == null && length(local.foundry_account.role_assignments) == 0
    error_message = "Foundry has network rules or role assignments nobody asked for."
  }

  assert {
    condition     = local.foundry_account.create_ai_agent_service == false && local.foundry_projects.main.create_project_connections == false
    error_message = "With the Agent Service dependencies off, Foundry still gets a capability host or connections (see agent_service.tftest.hcl)."
  }

  assert {
    condition     = output.foundry_project_endpoint == "https://aif-alz-dev-ab12.services.ai.azure.com/api/projects/proj-alz-dev"
    error_message = "The project endpoint is not built from the account and project names."
  }
}

run "ip_rules_and_project_users" {
  command = plan

  variables {
    allowed_ip_ranges = ["203.0.113.0/24"]
    project_user_principals = {
      deployers = {
        principal_id = "00000000-0000-0000-0000-00000000000a"
      }
    }
  }

  assert {
    condition     = local.foundry_account.network_acls.default_action == "Deny" && contains(local.foundry_account.network_acls.ip_rules, "203.0.113.0/24")
    error_message = "allowed_ip_ranges does not restrict Foundry."
  }

  assert {
    condition     = local.foundry_account.role_assignments["foundry-user-deployers"].principal_id == "00000000-0000-0000-0000-00000000000a" && local.foundry_account.role_assignments["foundry-user-deployers"].principal_type == "Group" && endswith(local.foundry_account.role_assignments["foundry-user-deployers"].role_definition_id_or_name, "53ca6127-db72-4b80-b1b0-d745d6d5456d")
    error_message = "A project user group does not get the Foundry User role."
  }
}

run "invalid_prefix" {
  command = plan

  variables {
    name_prefix = "toolongprefix"
  }

  expect_failures = [var.name_prefix]
}

run "no_model" {
  command = plan

  variables {
    model_deployments = {}
  }

  expect_failures = [var.model_deployments]
}
