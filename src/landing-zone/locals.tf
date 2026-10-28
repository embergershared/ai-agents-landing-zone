# Names follow <abbreviation>-<prefix>-<environment>-<suffix> (decision D7). The random suffix
# keeps global names unique and lets a soft-deleted Foundry account or Key Vault keep its name.
resource "random_string" "suffix" {
  length  = local.suffix_length
  special = false
  upper   = false
}

locals {
  suffix        = random_string.suffix.result
  suffix_length = 4

  # AI Search can run in another region than the rest (search_location).
  search_location = coalesce(var.search_location, var.location)

  # Name parts made compliant from the variables: lowercase letters and digits, any other run of
  # characters becomes one hyphen, and no hyphen at either end. Short plain values pass unchanged.
  name_prefix      = trim(replace(lower(var.name_prefix), "/[^a-z0-9]+/", "-"), "-")
  name_environment = trim(replace(lower(var.environment), "/[^a-z0-9]+/", "-"), "-")

  # When a name is too long, the prefix part is shortened, down to this many characters, before
  # the environment part.
  name_min_prefix = 3

  # Per name: head and tail around <prefix><separator><environment>, whether the random suffix
  # ends it, the type's maximum length, and compact for types without hyphens (no separator).
  name_specs = {
    resource_group = { head = "rg-", tail = "", suffix = true, max = 90, compact = false }
    log_analytics  = { head = "log-", tail = "", suffix = true, max = 63, compact = false }
    app_insights   = { head = "appi-", tail = "", suffix = true, max = 260, compact = false }
    key_vault      = { head = "kv-", tail = "", suffix = true, max = 24, compact = false }
    foundry        = { head = "aif-", tail = "", suffix = true, max = 64, compact = false }
    agent_cosmos   = { head = "cosmos-", tail = "", suffix = true, max = 44, compact = false }
    agent_search   = { head = "srch-", tail = "", suffix = true, max = 60, compact = false }
    agent_storage  = { head = "st", tail = "agent", suffix = true, max = 24, compact = true }
    project        = { head = "proj-", tail = "", suffix = false, max = 64, compact = false }
    app_config     = { head = "appcs-", tail = "", suffix = true, max = 50, compact = false }
    app_registry   = { head = "cr", tail = "", suffix = true, max = 50, compact = true }
    app_env        = { head = "cae-", tail = "", suffix = true, max = 60, compact = false }
    app_identity   = { head = "id-", tail = "-app", suffix = false, max = 128, compact = false }
    app_search     = { head = "srch-", tail = "-app", suffix = true, max = 60, compact = false }
    app_storage    = { head = "st", tail = "app", suffix = true, max = 24, compact = true }
  }

  name_parts = { for k, s in local.name_specs : k => {
    prefix = s.compact ? replace(local.name_prefix, "-", "") : local.name_prefix
    env    = s.compact ? replace(local.name_environment, "-", "") : local.name_environment
    sep    = s.compact ? "" : "-"
    # Characters left for <prefix><separator><environment>.
    budget = s.max - length(s.head) - length(s.tail) - (s.suffix ? local.suffix_length + (s.compact ? 0 : 1) : 0)
  } }

  name_env_parts = { for k, p in local.name_parts : k =>
    trim(substr(p.env, 0, max(1, min(length(p.env), p.budget - length(p.sep) - min(length(p.prefix), local.name_min_prefix)))), "-")
  }

  name_prefix_parts = { for k, p in local.name_parts : k =>
    trim(substr(p.prefix, 0, max(1, p.budget - length(p.sep) - length(local.name_env_parts[k]))), "-")
  }

  names = { for k, s in local.name_specs : k => join("", [
    s.head,
    local.name_prefix_parts[k],
    local.name_parts[k].sep,
    local.name_env_parts[k],
    s.tail,
    s.suffix ? "${local.name_parts[k].sep}${local.suffix}" : "",
  ]) }

  # The Foundry module's base_name (its capability host names): 3 to 9 lowercase letters, digits
  # or hyphens, starting and ending with a letter or digit.
  foundry_base_name_max = 9
  foundry_base_name     = trim(substr(local.name_prefix, 0, local.foundry_base_name_max), "-")

  tags = merge({ workload = "agent-landing-zone", environment = var.environment }, var.tags)

  # Role definition IDs stay the same when a role is renamed ("Azure AI User" is now "Foundry User").
  roles = {
    foundry_user                  = "53ca6127-db72-4b80-b1b0-d745d6d5456d"
    app_configuration_data_owner  = "5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b"
    app_configuration_data_reader = "516239f1-63e1-4d78-a4de-a74fb236a071"
    acr_pull                      = "7f951dda-4ed3-4680-a7ca-43fe172d538d"
    search_index_data_contributor = "8ebe5a00-799e-43f5-93ac-243d3dce84a7"
    storage_blob_data_contributor = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    storage_account_contributor   = "17d1049b-9a84-46fb-8f53-869881c3d3ab"
    monitoring_metrics_publisher  = "3913510d-42f4-4e42-8a64-420c390055eb"
    log_analytics_reader          = "73c42c96-874c-492b-b04d-ab87d138a893"
  }
}
