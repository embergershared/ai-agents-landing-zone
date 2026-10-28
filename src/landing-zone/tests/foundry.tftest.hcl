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

  mock_resource "azurerm_application_insights" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12/providers/Microsoft.Insights/components/appi-alz-dev-ab12"
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

# The project's tracing connection: azapi has no mock (the module's ephemeral resources need it).
override_resource {
  target          = azapi_resource.app_insights_connection
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
    ai_foundry_project_id = {
      main = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12/providers/Microsoft.CognitiveServices/accounts/aif-alz-dev-ab12/projects/proj-alz-dev"
    }
    ai_foundry_project_system_identity_principal_id = {
      main = "00000000-0000-0000-0000-00000000000b"
    }
    storage_account_id = {
      agent = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12/providers/Microsoft.Storage/storageAccounts/stalzdevagentab12"
    }
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

  # Short plain values must give the names existing environments already have.
  assert {
    condition = local.names == {
      resource_group = "rg-alz-dev-ab12"
      log_analytics  = "log-alz-dev-ab12"
      app_insights   = "appi-alz-dev-ab12"
      key_vault      = "kv-alz-dev-ab12"
      foundry        = "aif-alz-dev-ab12"
      agent_cosmos   = "cosmos-alz-dev-ab12"
      agent_search   = "srch-alz-dev-ab12"
      agent_storage  = "stalzdevagentab12"
      project        = "proj-alz-dev"
      app_config     = "appcs-alz-dev-ab12"
      app_registry   = "cralzdevab12"
      app_env        = "cae-alz-dev-ab12"
      app_identity   = "id-alz-dev-app"
      app_search     = "srch-alz-dev-app-ab12"
      app_storage    = "stalzdevappab12"
    } && local.foundry_base_name == "alz"
    error_message = "With name_prefix alz and environment dev, a name differs from the names before compliant naming."
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
    condition     = azapi_resource.app_insights_connection.body.properties.category == "AppInsights" && azapi_resource.app_insights_connection.body.properties.authType == "ProjectManagedIdentity" && azapi_resource.app_insights_connection.body.properties.target == azurerm_application_insights.this.id && endswith(azapi_resource.app_insights_connection.parent_id, "/projects/proj-alz-dev")
    error_message = "The project has no Application Insights connection through its managed identity."
  }

  assert {
    condition     = azurerm_role_assignment.project_trace_ingestion.scope == azurerm_application_insights.this.id && azurerm_role_assignment.project_trace_ingestion.principal_id == "00000000-0000-0000-0000-00000000000b" && endswith(azurerm_role_assignment.project_trace_ingestion.role_definition_id, "3913510d-42f4-4e42-8a64-420c390055eb")
    error_message = "The project identity can't publish traces to Application Insights (Monitoring Metrics Publisher)."
  }

  assert {
    condition     = length(azurerm_role_assignment.project_storage_account_contributor) == 0 && length(azurerm_role_assignment.project_user_traces) == 0
    error_message = "With the switch off and no project users, a storage or trace reader role is still planned."
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

  assert {
    condition     = azurerm_role_assignment.project_user_traces["deployers"].scope == azurerm_application_insights.this.id && endswith(azurerm_role_assignment.project_user_traces["deployers"].role_definition_id, "73c42c96-874c-492b-b04d-ab87d138a893")
    error_message = "A project user group can't read traces (Log Analytics Reader on Application Insights)."
  }
}

run "long_names" {
  command = plan

  variables {
    name_prefix = "swec-s3-ailz-agent-svc"
    environment = "fullrun"
  }

  assert {
    condition = alltrue([for k, n in local.names : length(n) <= local.name_specs[k].max && can(regex(
      local.name_specs[k].compact ? "^[a-z][a-z0-9]*$" : "^[a-z][a-z0-9]*(-[a-z0-9]+)*$", n
    ))])
    error_message = "A name is longer than its type allows, or has characters or hyphens it doesn't allow."
  }

  # The examples in docs/landing-zone.md, "Compliant names from any prefix and environment".
  assert {
    condition     = local.names.key_vault == "kv-swec-s3-fullrun-ab12" && local.names.agent_storage == "stswecs3fullrunagentab12" && local.names.app_storage == "stswecs3aifullrunappab12"
    error_message = "A shortened name doesn't keep the environment and shorten the prefix."
  }

  assert {
    condition     = local.names.app_registry == "crswecs3ailzagentsvcfullrunab12" && local.names.agent_cosmos == "cosmos-swec-s3-ailz-agent-svc-fullrun-ab12" && local.names.app_search == "srch-swec-s3-ailz-agent-svc-fullrun-app-ab12"
    error_message = "A name that fits its type's maximum length is shortened or loses the wrong characters."
  }

  assert {
    condition     = local.names.project == "proj-swec-s3-ailz-agent-svc-fullrun" && local.names.resource_group == "rg-swec-s3-ailz-agent-svc-fullrun-ab12"
    error_message = "A name that fits is shortened."
  }

  assert {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,7}[a-z0-9]$", local.foundry_base_name))
    error_message = "The Foundry module's base_name doesn't meet its rule."
  }
}

run "non_compliant_characters" {
  command = plan

  variables {
    name_prefix = "Contoso_AI  Lab"
    environment = "QA.1"
  }

  assert {
    condition     = local.names.resource_group == "rg-contoso-ai-lab-qa-1-ab12" && local.names.app_storage == "stcontosoailabqa1appab12"
    error_message = "Upper case, underscores, spaces or periods are not turned into compliant names."
  }

  assert {
    condition     = local.tags.environment == "QA.1"
    error_message = "The environment tag doesn't keep the environment as written."
  }
}

run "invalid_prefix" {
  command = plan

  variables {
    name_prefix = "a_b"
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
