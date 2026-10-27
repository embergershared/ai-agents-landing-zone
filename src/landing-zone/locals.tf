# Names follow <abbreviation>-<prefix>-<environment>-<suffix> (decision D7). The random suffix
# keeps global names unique and lets a soft-deleted Foundry account or Key Vault keep its name.
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

locals {
  suffix = random_string.suffix.result
  base   = "${var.name_prefix}-${var.environment}"

  names = {
    resource_group = "rg-${local.base}-${local.suffix}"
    log_analytics  = "log-${local.base}-${local.suffix}"
    app_insights   = "appi-${local.base}-${local.suffix}"
    key_vault      = "kv-${local.base}-${local.suffix}"
    foundry        = "aif-${local.base}-${local.suffix}"
    project        = "proj-${local.base}"
  }

  tags = merge({ workload = "agent-landing-zone", environment = var.environment }, var.tags)

  # Role definition IDs stay the same when a role is renamed ("Azure AI User" is now "Foundry User").
  roles = {
    foundry_user = "53ca6127-db72-4b80-b1b0-d745d6d5456d"
  }
}
