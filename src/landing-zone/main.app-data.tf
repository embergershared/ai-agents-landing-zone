# Application data (deploy_application_data): the applications' own AI Search and Storage,
# separate from the Agent Service's. Entra ID only; allowed_ip_ranges feeds their network rules.
resource "azurerm_search_service" "app" {
  count = local.app_data ? 1 : 0

  name                          = local.names.app_search
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  sku                           = var.app_search_sku
  replica_count                 = 1
  partition_count               = 1
  local_authentication_enabled  = false
  public_network_access_enabled = true
  allowed_ips                   = var.allowed_ip_ranges
  network_rule_bypass_option    = length(var.allowed_ip_ranges) == 0 ? "None" : "AzureServices"
  tags                          = local.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_storage_account" "app" {
  count = local.app_data ? 1 : 0

  name                            = local.names.app_storage
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
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
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "app_search" {
  count = local.app_data ? 1 : 0

  name                       = "to-log-analytics"
  target_resource_id         = azurerm_search_service.app[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# The applications' identity reads and writes the data, when the platform is deployed too.
# One resource per service, so one service's failure doesn't hold back the other's role.
resource "azurerm_role_assignment" "app_search_index" {
  count = local.app_data && local.app_platform ? 1 : 0

  scope              = azurerm_search_service.app[0].id
  role_definition_id = local.role_ids.search_index_data_contributor
  principal_id       = azurerm_user_assigned_identity.app[0].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "app_blob_data" {
  count = local.app_data && local.app_platform ? 1 : 0

  scope              = azurerm_storage_account.app[0].id
  role_definition_id = local.role_ids.storage_blob_data_contributor
  principal_id       = azurerm_user_assigned_identity.app[0].principal_id
  principal_type     = "ServicePrincipal"
}
