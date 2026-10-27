data "azurerm_client_config" "current" {}

# Storage account names are global: a short random suffix keeps them unique, and lets a
# soft-deleted or retired account's name stay unused.
resource "random_string" "suffix" {
  length  = local.suffix_length
  special = false
  upper   = false
}

locals {
  tags = merge({ workload = "agent-landing-zone", component = "state-backend" }, var.tags)

  suffix_length = 4

  # The prefix made compliant (as in the landing zone): lowercase letters and digits, any other run
  # of characters becomes one hyphen, none at either end; the storage account drops the hyphens.
  # Each name shortens it to fit the type's maximum length (resource group 90, storage account 24,
  # managed identity 128). Short plain values pass unchanged.
  name_prefix         = trim(replace(lower(var.name_prefix), "/[^a-z0-9]+/", "-"), "-")
  name_prefix_compact = replace(local.name_prefix, "-", "")

  resource_group_name  = "rg-${trim(substr(local.name_prefix, 0, 90 - length("rg--tfstate-") - local.suffix_length), "-")}-tfstate-${random_string.suffix.result}"
  storage_account_name = "st${substr(local.name_prefix_compact, 0, 24 - length("sttfstate") - local.suffix_length)}tfstate${random_string.suffix.result}"
  deployer_name        = "id-${trim(substr(local.name_prefix, 0, 128 - length("id--github-deployer")), "-")}-github-deployer"

  state_contributors = setunion(
    var.state_contributor_principal_ids,
    var.grant_current_principal ? [data.azurerm_client_config.current.object_id] : []
  )
}

resource "azurerm_resource_group" "state" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "state" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  access_tier              = "Hot"

  # Entra ID only: no shared key, no SAS, no SFTP local users, no anonymous access.
  shared_access_key_enabled       = false
  local_user_enabled              = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = true

  # Only with allowed_ip_ranges: the provider reads an allow-all rule set back as absent, so an
  # explicit one would show as a change on every plan. No block means all networks.
  dynamic "network_rules" {
    for_each = length(var.allowed_ip_ranges) == 0 ? [] : [var.allowed_ip_ranges]
    content {
      default_action = "Deny"
      ip_rules       = network_rules.value
      bypass         = ["AzureServices"]
    }
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }

  tags = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# Created through the management plane (storage_account_id), so no data-plane key is needed.
resource "azurerm_storage_container" "state" {
  for_each = var.environments

  name                  = "tfstate-${each.value}"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "state_contributor" {
  for_each = local.state_contributors

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}
