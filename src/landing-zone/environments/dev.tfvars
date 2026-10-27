# dev environment (decision D4: one state and one tfvars per environment). No secrets and no
# real IDs here: the Entra principals come from the PROJECT_USER_PRINCIPALS_DEV repository
# variable, the subscription from AZURE_SUBSCRIPTION_ID (docs/ci-cd.md).
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

# Off in dev until the subscription allows public network access on Cosmos DB and Storage (see
# docs/state-backend.md); then the standard setup can be turned on.
deploy_agent_service_dependencies = false

deploy_application_platform = true
deploy_application_data     = true

allowed_ip_ranges = []
