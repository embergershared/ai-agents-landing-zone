# dev environment (decision D4: one state and one tfvars per environment). No secrets and no
# real IDs here: the Entra principals come from the PROJECT_USER_PRINCIPALS_DEV repository
# secret, the subscription from AZURE_SUBSCRIPTION_ID (docs/ci-cd.md).
location    = "swedencentral"
name_prefix = "alz"
environment = "dev"

model_deployments = {
  "gpt-5.4-mini" = {
    model_name    = "gpt-5.4-mini"
    model_version = "2026-03-17"
    sku           = "GlobalStandard"
    capacity      = 10
  }
}

# Standard agent setup: our own Cosmos DB, AI Search and Storage.
deploy_agent_service_dependencies = true

# AI Search in Norway East: swedencentral had no AI Search capacity (Basic or Standard) on
# 2026-10-27; norwayeast is the closest region that had (owner's choice).
search_location = "norwayeast"

# Workload group: App Configuration, Container Registry, Container Apps, Key Vault, and the
# applications' own AI Search and Storage.
deploy_workload = true

allowed_ip_ranges = []

# Owner decision (2026-10-27): this subscription's Azure Policy turns off public network access
# on Storage, Key Vault and Cosmos DB unless they or their resource group carry this tag
# (docs/state-backend.md).
tags = {
  SecurityControl = "Ignore"
}
