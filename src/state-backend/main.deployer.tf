# Pipeline identity for GitHub Actions (github_deployer): a user-assigned managed identity that
# GitHub signs in as through OIDC (workload identity federation), so no client secret exists.
# Per environment it gets Contributor and a Role Based Access Control Administrator limited to
# the roles the landing zone grants, on that environment's scope, plus read and write on state.
locals {
  deployer = var.github_deployer != null

  # GitHub's OIDC subjects: one per environment (apply jobs) and one for pull requests (plans).
  # A repository with immutable subjects sends its owner and repository IDs in the prefix.
  deployer_subject_prefix = local.deployer ? coalesce(var.github_deployer.subject_prefix, "repo:${var.github_deployer.repository}") : null
  deployer_subjects = local.deployer ? merge(
    { for env in keys(var.github_deployer.environments) : "env-${env}" => "${local.deployer_subject_prefix}:environment:${env}" },
    { "pull-request" = "${local.deployer_subject_prefix}:pull_request" }
  ) : {}

  # The RBAC Administrator may only write or delete assignments of these roles.
  deployer_role_guids = join(", ", var.deployer_assignable_role_ids)
  deployer_rbac_condition = join(" AND ", [
    "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.deployer_role_guids}}))",
    "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.deployer_role_guids}}))",
  ])

  deployer_role_ids = {
    contributor = "b24988ac-6180-42a0-ab88-20f7382dd24c"
    rbac_admin  = "f58310d9-a9f6-439a-9e8d-f62e7b41a168"
    # Data plane of the environment's App Configuration (the landing zone's settings).
    app_configuration_data_owner = "5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b"
  }
}

resource "azurerm_user_assigned_identity" "deployer" {
  count = local.deployer ? 1 : 0

  name                = "id-${var.name_prefix}-github-deployer"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "deployer" {
  for_each = local.deployer_subjects

  name                      = each.key
  user_assigned_identity_id = azurerm_user_assigned_identity.deployer[0].id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = each.value
}

resource "azurerm_role_assignment" "deployer_contributor" {
  for_each = local.deployer ? var.github_deployer.environments : {}

  scope              = each.value
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.deployer_role_ids.contributor}"
  principal_id       = azurerm_user_assigned_identity.deployer[0].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deployer_rbac_admin" {
  for_each = local.deployer ? var.github_deployer.environments : {}

  scope              = each.value
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.deployer_role_ids.rbac_admin}"
  principal_id       = azurerm_user_assigned_identity.deployer[0].principal_id
  principal_type     = "ServicePrincipal"
  condition          = local.deployer_rbac_condition
  condition_version  = "2.0"
}

# The landing zone's plans read App Configuration settings through the data plane: the identity
# needs the role before its first plan, so it can't come from the landing zone itself.
resource "azurerm_role_assignment" "deployer_app_settings" {
  for_each = local.deployer ? var.github_deployer.environments : {}

  scope              = each.value
  role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${local.deployer_role_ids.app_configuration_data_owner}"
  principal_id       = azurerm_user_assigned_identity.deployer[0].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deployer_state" {
  count = local.deployer ? 1 : 0

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.deployer[0].principal_id
  principal_type       = "ServicePrincipal"
}
