# Names follow <abbreviation>-<prefix>-<environment>-<suffix> (decision D7). The random suffix
# keeps global names unique and lets a soft-deleted Foundry account or Key Vault keep its name.
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

locals {
  suffix = random_string.suffix.result

  # AI Search can run in another region than the rest (search_location).
  search_location = coalesce(var.search_location, var.location)
  base            = "${var.name_prefix}-${var.environment}"

  names = {
    resource_group = "rg-${local.base}-${local.suffix}"
    log_analytics  = "log-${local.base}-${local.suffix}"
    app_insights   = "appi-${local.base}-${local.suffix}"
    key_vault      = "kv-${local.base}-${local.suffix}"
    foundry        = "aif-${local.base}-${local.suffix}"
    agent_cosmos   = "cosmos-${local.base}-${local.suffix}"
    agent_search   = "srch-${local.base}-${local.suffix}"
    agent_storage  = "st${var.name_prefix}${var.environment}agent${local.suffix}"
    project        = "proj-${local.base}"
    app_config     = "appcs-${local.base}-${local.suffix}"
    app_registry   = "cr${var.name_prefix}${var.environment}${local.suffix}"
    app_env        = "cae-${local.base}-${local.suffix}"
    app_identity   = "id-${local.base}-app"
    app_search     = "srch-${local.base}-app-${local.suffix}"
    app_storage    = "st${var.name_prefix}${var.environment}app${local.suffix}"
  }

  tags = merge({ workload = "agent-landing-zone", environment = var.environment }, var.tags)

  # Role definition IDs stay the same when a role is renamed ("Azure AI User" is now "Foundry User").
  roles = {
    foundry_user                  = "53ca6127-db72-4b80-b1b0-d745d6d5456d"
    app_configuration_data_owner  = "5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b"
    app_configuration_data_reader = "516239f1-63e1-4d78-a4de-a74fb236a071"
    acr_pull                      = "7f951dda-4ed3-4680-a7ca-43fe172d538d"
    search_index_data_contributor = "8ebe5a00-799e-43f5-93ac-243d3dce84a7"
    storage_blob_data_contributor = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
  }
}
