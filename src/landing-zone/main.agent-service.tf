# The Foundry Agent Service dependencies switch (deployment plan, "The Agent Service
# dependencies switch"). On: the standard agent setup with our own Cosmos DB, AI Search and
# Storage, their project connections, capability hosts and RBAC. Off: the basic setup, with
# Microsoft-managed storage. With existing_agent_service_dependencies, an existing dedicated
# set is connected instead of creating one. AI Search is created outside the module (below).
locals {
  agent_service_enabled = var.deploy_agent_service_dependencies
  agent_deps_existing   = local.agent_service_enabled && var.existing_agent_service_dependencies != null
  agent_deps_create     = local.agent_service_enabled && !local.agent_deps_existing

  # Map key of the dependency set the module creates and the project connects to.
  agent_deps_key = "agent"

  agent_cosmos_db_definition = local.agent_deps_create ? {
    (local.agent_deps_key) = {
      name                          = local.names.agent_cosmos
      public_network_access_enabled = true
      local_authentication_disabled = true
      automatic_failover_enabled    = false
      # Empty: all networks. With allowed_ip_ranges, also 0.0.0.0 (Azure datacenters), which the
      # Agent Service needs.
      ip_range_filter = length(var.allowed_ip_ranges) == 0 ? [] : concat(var.allowed_ip_ranges, ["0.0.0.0"])
      capabilities    = var.agent_cosmos_db_serverless ? [{ name = "EnableServerless" }] : []
      capacity = {
        total_throughput_limit = var.agent_cosmos_db_serverless ? -1 : var.agent_cosmos_db_total_throughput_limit
      }
      secondary_regions = []
      diagnostic_settings = {
        to_log_analytics = {
          name                  = "to-log-analytics"
          workspace_resource_id = azurerm_log_analytics_workspace.this.id
          # Cosmos DB accepts only these two metric categories in a diagnostic setting.
          metric_categories = ["SLI", "Requests"]
        }
      }
    }
  } : {}

  agent_storage_definition = local.agent_deps_create ? {
    (local.agent_deps_key) = {
      name                          = local.names.agent_storage
      account_replication_type      = "ZRS"
      shared_access_key_enabled     = false
      public_network_access_enabled = true
      network_rules = length(var.allowed_ip_ranges) == 0 ? null : {
        bypass         = ["AzureServices"]
        default_action = "Deny"
        ip_rules       = var.allowed_ip_ranges
      }
    }
  } : {}

  # The project's connections: to the new set, to the existing one, or none.
  agent_project_connections = !local.agent_service_enabled ? {
    cosmos_db_connection       = {}
    ai_search_connection       = {}
    storage_account_connection = {}
    } : local.agent_deps_existing ? {
    cosmos_db_connection       = { existing_resource_id = var.existing_agent_service_dependencies.cosmos_db_resource_id }
    ai_search_connection       = { existing_resource_id = var.existing_agent_service_dependencies.ai_search_resource_id }
    storage_account_connection = { existing_resource_id = var.existing_agent_service_dependencies.storage_account_resource_id }
    } : {
    cosmos_db_connection       = { new_resource_map_key = local.agent_deps_key }
    ai_search_connection       = { existing_resource_id = azurerm_search_service.agent[0].id }
    storage_account_connection = { new_resource_map_key = local.agent_deps_key }
  }
}

# The Agent Service's AI Search is created here, not by the Foundry module, so it can live in
# search_location: the module creates everything in one region, and a region can run out of
# AI Search capacity. The project connects to it as an existing resource.
resource "azurerm_search_service" "agent" {
  count = local.agent_deps_create ? 1 : 0

  name                          = local.names.agent_search
  resource_group_name           = azurerm_resource_group.this.name
  location                      = local.search_location
  sku                           = var.agent_search_sku
  replica_count                 = var.agent_search_replica_count
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

resource "azurerm_monitor_diagnostic_setting" "agent_search" {
  count = local.agent_deps_create ? 1 : 0

  name                       = "to-log-analytics"
  target_resource_id         = azurerm_search_service.agent[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
