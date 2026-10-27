# Landing zone root module

`src/landing-zone/` deploys one environment of the Agent Landing Zone on public endpoints. It
uses the Foundry AVM pattern module `Azure/avm-ptn-aiml-ai-foundry/azurerm` 0.12.0, with
`create_private_endpoints = false`. The design and the phases are in
[deployment-plan.md](deployment-plan.md).

## What it deploys

| Area | File | Resources |
|---|---|---|
| Core | `main.core.tf` | Resource group; Log Analytics (key auth off); workspace-based Application Insights (key auth off); Key Vault (RBAC authorization, purge protection, 90-day soft delete, diagnostics to Log Analytics). |
| Foundry | `main.foundry.tf` | Foundry (AI Services) account with key auth off and public endpoint on; one project; the model deployments; diagnostics to Log Analytics; Foundry User for `project_user_principals`. |
| Application platform | `main.app-platform.tf` | Behind `deploy_application_platform`: App Configuration (key auth off) holding the landing zone's endpoints and names, labeled with the environment; Container Registry (no admin user, no anonymous pull); Container Apps environment (logs to Log Analytics through a diagnostic setting); the applications' user-assigned identity, with App Configuration Data Reader, AcrPull and Foundry User. |
| Application data | `main.app-data.tf` | Behind `deploy_application_data`: the applications' own AI Search and Storage (key auth off), with Search Index Data Contributor and Storage Blob Data Contributor for the applications' identity. |
| Agent Service | `main.agent-service.tf` | Behind `deploy_agent_service_dependencies`: Cosmos DB (serverless by default), AI Search and Storage, all with key auth off and public endpoints; the project's connections to them, the account and project capability hosts, and the RBAC the Agent Service needs. The Foundry module creates Cosmos DB and Storage. AI Search is created next to it, so it can live in `search_location`, and the project connects to it as an existing resource. |

Names follow `<abbreviation>-<prefix>-<environment>-<suffix>` (`rg-alz-dev-ab12`,
`aif-alz-dev-ab12`, `kv-alz-dev-ab12`); the project is `proj-<prefix>-<environment>`.

## Inputs

| Variable | Default | Meaning |
|---|---|---|
| `location` | `swedencentral` | Region; it must offer the models with quota. |
| `search_location` | `location` | Region of the two AI Search services, for a region without AI Search capacity. Dev uses `norwayeast`. |
| `name_prefix` | `alz` | 3 to 7 lowercase letters or digits. |
| `environment` | `dev` | Part of every name. |
| `model_deployments` | `gpt-5.4-mini` 2026-03-17, GlobalStandard, 10K TPM | Deployments by name. |
| `project_user_principals` | none | Entra groups that use the project (Foundry User role). |
| `allowed_ip_ranges` | none | Empty means all networks; Entra ID is always required. |
| `log_analytics_retention_days` | 30 | 30 to 730. |
| `tags` | none | Added to the `workload` and `environment` tags. |
| `enable_telemetry` | `false` | AVM usage telemetry. |
| `deploy_agent_service_dependencies` | `true` | Standard agent setup (on) or basic setup (off). |
| `existing_agent_service_dependencies` | none | Resource IDs of an existing dedicated Cosmos DB, AI Search and Storage to connect instead of creating them. |
| `agent_cosmos_db_serverless` | `true` | Serverless Cosmos DB; off: provisioned, with `agent_cosmos_db_total_throughput_limit` (-1 or at least 3000 RU/s). |
| `agent_search_sku`, `agent_search_replica_count` | `basic`, 1 | AI Search for the Agent Service. |
| `deploy_application_platform` | `true` | App Configuration, Container Registry, Container Apps environment, applications' identity (decision D2). |
| `deploy_application_data` | `true` | The applications' AI Search and Storage (decision D2). |
| `app_configuration_sku`, `container_registry_sku`, `app_search_sku` | `standard`, `Basic`, `basic` | SKUs of the application resources. |

`terraform.tfvars.example` shows them all; copy it to `terraform.tfvars` (gitignored).

## Deploy (PowerShell, workstation)

```powershell
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
$env:ARM_SUBSCRIPTION_ID = az account show --query id -o tsv

Set-Location src/landing-zone
# dev.backend.hcl: copy environments/dev.backend.hcl.example, fill it from the
# state-backend's backend_config output (see docs/state-backend.md)
terraform init -backend-config=environments/dev.backend.hcl
terraform plan -out dev.tfplan
# Read the plan, then apply only after the go-ahead
terraform apply dev.tfplan
```

## Verify: a model call with an Entra ID token

```powershell
$endpoint = terraform output -raw foundry_openai_endpoint
$token = az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv
$body = @{ model = 'gpt-5.4-mini'; messages = @(@{ role = 'user'; content = 'Reply with exactly: landing zone ok' }); max_completion_tokens = 20 } | ConvertTo-Json -Depth 5
Invoke-RestMethod -Method Post -Uri "${endpoint}openai/v1/chat/completions" -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $body |
  Select-Object -ExpandProperty choices | ForEach-Object { $_.message.content }
```

The caller needs the Foundry User role on the account (through `project_user_principals`).
A call with an `api-key` header gets 401: key authentication is off.

## Settings in App Configuration

With the platform on, Terraform writes these keys, labeled with the environment (`dev`),
through the data plane. Whoever runs Terraform needs App Configuration Data Owner, even for a
plan: the pipeline identity gets it from `src/state-backend`, and people who run Terraform from
a workstation are listed in `app_settings_writer_principals`.

| Key | Value |
|---|---|
| `landingzone:foundry:openai_endpoint` | OpenAI-compatible endpoint of the Foundry account |
| `landingzone:foundry:project_endpoint` | Foundry project endpoint |
| `landingzone:foundry:models` | Model deployment names, comma-separated |
| `landingzone:agent_service:setup` | `standard` or `basic` |
| `landingzone:key_vault:uri` | Key Vault URI |
| `landingzone:app_insights:connection` | Application Insights connection string |
| `landingzone:app_data:search_endpoint`, `landingzone:app_data:blob_endpoint` | Application data endpoints (data on) |

An application running as the applications' identity reads them with Entra ID, for example
`az appconfig kv list --endpoint <endpoint> --auth-mode login --label dev` after
`az login --identity --client-id <client-id>`.

## The Agent Service dependencies switch

| `deploy_agent_service_dependencies` | `existing_agent_service_dependencies` | Result |
|---|---|---|
| `true` | not set | Standard setup: new Cosmos DB, AI Search and Storage, connected to the project, with capability hosts and RBAC. |
| `true` | set | Standard setup on the existing set: connections, capability hosts and RBAC only. |
| `false` | ignored | Basic setup: agents keep threads and files in Microsoft-managed storage. |

The switch sets the Foundry module's `create_byor`, `ai_foundry.create_ai_agent_service` and
the project's `create_project_connections` together (see `main.agent-service.tf`).
`terraform test` covers the three rows. In the standard setup, the Agent Service reaches
Cosmos DB and Storage on their public endpoints. A policy that turns those endpoints off breaks
it (see [state-backend.md](state-backend.md)).

Check an agent, with a token for `https://ai.azure.com` (PowerShell):
```powershell
$project = terraform output -raw foundry_project_endpoint
$h = @{ Authorization = "Bearer $(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)" }
$agent = Invoke-RestMethod -Method Post -Uri "$project/assistants?api-version=v1" -Headers $h -ContentType 'application/json' `
  -Body (@{ model = 'gpt-5.4-mini'; name = 'lz-smoke'; instructions = 'Answer in five words or fewer.' } | ConvertTo-Json)
$run = Invoke-RestMethod -Method Post -Uri "$project/threads/runs?api-version=v1" -Headers $h -ContentType 'application/json' `
  -Body (@{ assistant_id = $agent.id; thread = @{ messages = @(@{ role = 'user'; content = 'Say: agents work' }) } } | ConvertTo-Json -Depth 5)
# When the run's status is completed:
(Invoke-RestMethod -Uri "$project/threads/$($run.thread_id)/messages?api-version=v1" -Headers $h).data | ForEach-Object { $_.content.text.value }
Invoke-RestMethod -Method Delete -Uri "$project/assistants/$($agent.id)?api-version=v1" -Headers $h
```

## Known plan noise

- **Foundry diagnostic setting:** every plan shows `log_analytics_destination_type` being set,
  because Azure doesn't keep that value on a Foundry account. This is harmless.
- **Public network access under a policy that turns it off:** in a subscription where Azure
  Policy sets `publicNetworkAccess = Disabled` and the environment doesn't carry the policy's
  exemption (see [state-backend.md](state-backend.md)),
  every plan shows Key Vault's `public_network_access_enabled` changing back to `true`, and
  Key Vault refuses calls from outside Azure. A policy that covers only Storage, Key Vault and
  Cosmos DB leaves the Foundry account's public endpoint on.
