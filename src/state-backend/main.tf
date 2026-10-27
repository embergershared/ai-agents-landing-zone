data "azurerm_client_config" "current" {}

# Storage account names are global: a short random suffix keeps them unique, and lets a
# soft-deleted or retired account's name stay unused.
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

locals {
  tags = merge({ workload = "agent-landing-zone", component = "state-backend" }, var.tags)

  resource_group_name  = "rg-${var.name_prefix}-tfstate-${random_string.suffix.result}"
  storage_account_name = "st${var.name_prefix}tfstate${random_string.suffix.result}"

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

  network_rules {
    default_action = length(var.allowed_ip_ranges) == 0 ? "Allow" : "Deny"
    ip_rules       = var.allowed_ip_ranges
    bypass         = ["AzureServices"]
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
