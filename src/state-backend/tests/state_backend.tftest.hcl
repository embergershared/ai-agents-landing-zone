# Offline: the providers are mocked, nothing is created in Azure. override_during = plan makes
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

  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-tfstate-ab12/providers/Microsoft.Storage/storageAccounts/stalztfstateab12"
    }
  }

  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-tfstate-ab12/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-alz-github-deployer"
      principal_id = "00000000-0000-0000-0000-0000000000d1"
      client_id    = "00000000-0000-0000-0000-0000000000d2"
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

run "defaults" {
  command = plan

  variables {
    github_deployer = null
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.deployer) == 0 && length(azurerm_federated_identity_credential.deployer) == 0 && output.github_deployer == null
    error_message = "Without github_deployer, a pipeline identity is planned."
  }

  assert {
    condition     = azurerm_storage_account.state.name == "stalztfstateab12"
    error_message = "Storage account name is not st<prefix>tfstate<suffix>."
  }

  assert {
    condition     = length(azurerm_storage_account.state.name) <= 24
    error_message = "Storage account name is longer than 24 characters."
  }

  assert {
    condition     = azurerm_storage_account.state.shared_access_key_enabled == false && azurerm_storage_account.state.default_to_oauth_authentication == true
    error_message = "Shared key access is not off, or Entra ID is not the default."
  }

  assert {
    condition     = azurerm_storage_account.state.min_tls_version == "TLS1_2" && azurerm_storage_account.state.https_traffic_only_enabled == true
    error_message = "TLS 1.2 and HTTPS only are not enforced."
  }

  assert {
    condition     = azurerm_storage_account.state.allow_nested_items_to_be_public == false && azurerm_storage_account.state.local_user_enabled == false
    error_message = "Anonymous blob access or SFTP local users are allowed."
  }

  assert {
    condition     = azurerm_storage_account.state.blob_properties[0].versioning_enabled == true
    error_message = "Blob versioning is off."
  }

  assert {
    condition     = azurerm_storage_account.state.blob_properties[0].delete_retention_policy[0].days == 30 && azurerm_storage_account.state.blob_properties[0].container_delete_retention_policy[0].days == 30
    error_message = "Soft delete of blobs and containers is not 30 days."
  }

  assert {
    condition     = azurerm_storage_account.state.network_rules[0].default_action == "Allow"
    error_message = "With no allowed_ip_ranges, the account is not open to all networks."
  }

  assert {
    condition     = keys(azurerm_storage_container.state) == ["dev"] && azurerm_storage_container.state["dev"].name == "tfstate-dev"
    error_message = "The default environment does not get the tfstate-dev container."
  }

  assert {
    condition     = keys(azurerm_role_assignment.state_contributor) == ["00000000-0000-0000-0000-000000000001"]
    error_message = "The identity running the bootstrap does not get state access."
  }

  assert {
    condition     = output.backend_config["dev"].use_azuread_auth == true && output.backend_config["dev"].container_name == "tfstate-dev"
    error_message = "The backend settings don't use Entra ID or the environment's container."
  }
}

run "environments_contributors_and_ip_rules" {
  command = plan

  variables {
    environments                    = ["dev", "prod"]
    state_contributor_principal_ids = ["00000000-0000-0000-0000-00000000000a"]
    grant_current_principal         = false
    allowed_ip_ranges               = ["203.0.113.0/24"]
  }

  assert {
    condition     = length(azurerm_storage_container.state) == 2 && azurerm_storage_container.state["prod"].name == "tfstate-prod"
    error_message = "Each environment does not get its own container."
  }

  assert {
    condition     = keys(azurerm_role_assignment.state_contributor) == ["00000000-0000-0000-0000-00000000000a"]
    error_message = "State access is not limited to the listed principals."
  }

  assert {
    condition     = azurerm_storage_account.state.network_rules[0].default_action == "Deny" && contains(azurerm_storage_account.state.network_rules[0].ip_rules, "203.0.113.0/24")
    error_message = "allowed_ip_ranges does not restrict the account."
  }
}

run "invalid_prefix" {
  command = plan

  variables {
    name_prefix = "Not_Valid"
  }

  expect_failures = [var.name_prefix]
}

run "no_environment" {
  command = plan

  variables {
    environments = []
  }

  expect_failures = [var.environments]
}

run "github_deployer" {
  command = plan

  variables {
    github_deployer = {
      repository = "contoso/landing-zone"
      environments = {
        dev = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12"
      }
    }
  }

  assert {
    condition     = azurerm_user_assigned_identity.deployer[0].name == "id-alz-github-deployer"
    error_message = "The pipeline identity is missing or misnamed."
  }

  assert {
    condition     = azurerm_federated_identity_credential.deployer["env-dev"].subject == "repo:contoso/landing-zone:environment:dev" && azurerm_federated_identity_credential.deployer["pull-request"].subject == "repo:contoso/landing-zone:pull_request"
    error_message = "The federated credentials don't trust the environment and pull requests of the repository."
  }

  assert {
    condition     = azurerm_federated_identity_credential.deployer["env-dev"].issuer == "https://token.actions.githubusercontent.com" && contains(azurerm_federated_identity_credential.deployer["env-dev"].audience, "api://AzureADTokenExchange")
    error_message = "The federated credential doesn't use GitHub's OIDC issuer and audience."
  }

  assert {
    condition     = azurerm_role_assignment.deployer_contributor["dev"].scope == "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12" && endswith(azurerm_role_assignment.deployer_contributor["dev"].role_definition_id, "b24988ac-6180-42a0-ab88-20f7382dd24c")
    error_message = "The pipeline identity is not Contributor on the environment's scope."
  }

  assert {
    condition     = azurerm_role_assignment.deployer_rbac_admin["dev"].condition_version == "2.0" && strcontains(azurerm_role_assignment.deployer_rbac_admin["dev"].condition, "53ca6127-db72-4b80-b1b0-d745d6d5456d") && strcontains(azurerm_role_assignment.deployer_rbac_admin["dev"].condition, "roleAssignments/delete")
    error_message = "The RBAC Administrator role is not limited to the landing zone's roles."
  }

  assert {
    condition     = strcontains(azurerm_role_assignment.deployer_rbac_admin["dev"].condition, "b24988ac-6180-42a0-ab88-20f7382dd24c") == false
    error_message = "The pipeline identity could hand out Contributor."
  }

  assert {
    condition     = azurerm_role_assignment.deployer_state[0].scope == azurerm_storage_account.state.id && azurerm_role_assignment.deployer_state[0].principal_id == "00000000-0000-0000-0000-0000000000d1"
    error_message = "The pipeline identity can't read and write state."
  }
}

run "github_deployer_immutable_subject" {
  command = plan

  variables {
    github_deployer = {
      repository     = "contoso/landing-zone"
      subject_prefix = "repo:contoso@111/landing-zone@222"
      environments = {
        dev = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-alz-dev-ab12"
      }
    }
  }

  assert {
    condition     = azurerm_federated_identity_credential.deployer["env-dev"].subject == "repo:contoso@111/landing-zone@222:environment:dev" && azurerm_federated_identity_credential.deployer["pull-request"].subject == "repo:contoso@111/landing-zone@222:pull_request"
    error_message = "The federated credentials don't use the immutable subject prefix."
  }
}

run "invalid_subject_prefix" {
  command = plan

  variables {
    github_deployer = {
      repository     = "contoso/landing-zone"
      subject_prefix = "contoso/landing-zone"
      environments   = {}
    }
  }

  expect_failures = [var.github_deployer]
}

run "invalid_repository" {
  command = plan

  variables {
    github_deployer = {
      repository   = "not a repository"
      environments = {}
    }
  }

  expect_failures = [var.github_deployer]
}
