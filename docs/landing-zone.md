# Landing zone root module

`src/landing-zone/` deploys one environment of the Agent Landing Zone on public endpoints. It
uses the Foundry AVM pattern module `Azure/avm-ptn-aiml-ai-foundry/azurerm` 0.12.0, with
`create_private_endpoints = false`. The design and the phases are in
[deployment-plan.md](deployment-plan.md).

## What it deploys

The resources fall into three groups, one file each, all in one resource group and one
Terraform state per environment (decision D8). Groups 2 and 3 build on group 1, not on each
other: either can be on or off alone.

| Group | File | Switch | Resources |
|---|---|---|---|
| 1. Foundry essentials | `main.foundry.tf` | none: always | Resource group; Log Analytics (key auth off); workspace-based Application Insights (key auth off); Foundry (AI Services) account with key auth off and public endpoint on; one project; the model deployments; diagnostics to Log Analytics; Foundry User on the account for `project_user_principals` (decision [0001](decisions/0001-standard-agent-setup-gaps.md)); the project's Application Insights connection for agent traces, through the project's managed identity (Monitoring Metrics Publisher), and Log Analytics Reader on Application Insights for `project_user_principals` to see the traces. |
| 2. Agent Service dependencies | `main.agent-service.tf` | `deploy_agent_service_dependencies` | Cosmos DB (serverless by default), AI Search and Storage, all with key auth off and public endpoints; the project's connections to them, the account and project capability hosts, and the RBAC the Agent Service needs, plus Storage Account Contributor for the project on the storage account (new or existing). No Key Vault: see decision [0001](decisions/0001-standard-agent-setup-gaps.md). The Foundry module creates Cosmos DB and Storage. AI Search is created next to it, so it can live in `search_location`, and the project connects to it as an existing resource. |
| 3. Workload | `main.workload.tf` | `deploy_workload` | App Configuration (key auth off) holding the landing zone's endpoints and names, labeled with the environment; Container Registry (no admin user, no anonymous pull); Container Apps environment (logs to Log Analytics through a diagnostic setting); the applications' user-assigned identity, with App Configuration Data Reader, AcrPull and Foundry User; Key Vault for the applications' secrets (RBAC authorization, purge protection, 90-day soft delete, diagnostics to Log Analytics); the applications' own AI Search and Storage (key auth off), with Search Index Data Contributor and Storage Blob Data Contributor for the applications' identity. |

Names follow `<abbreviation>-<prefix>-<environment>-<suffix>` (`rg-alz-dev-ab12`,
`aif-alz-dev-ab12`, `kv-alz-dev-ab12`); the project is `proj-<prefix>-<environment>`.

### Compliant names from any prefix and environment

`locals.tf` builds every name so it meets its type's Azure rules, whatever `name_prefix` and
`environment` hold (issue #50):

1. **Characters:** letters and digits are kept in lowercase; any other run of characters
   (space, underscore, period, hyphens) becomes one hyphen, and none is left at either end.
   Storage accounts and Container Registry drop the hyphens.
2. **Length:** when a name would pass its type's maximum, the prefix part is shortened first
   (down to 3 characters), then the environment part. The abbreviation, the `-app`/`agent`
   parts and the random suffix stay.
3. **Unchanged when it fits:** short plain values, such as `alz` and `dev`, give the same names
   as before; `terraform test` checks every name for `alz`/`dev`.

| Name | Maximum | Example for `swec-s3-ailz-agent-svc` / `fullrun` |
|---|---|---|
| Resource group | 90 | `rg-swec-s3-ailz-agent-svc-fullrun-ab12` |
| Key Vault | 24 | `kv-swec-s3-fullrun-ab12` |
| Storage accounts | 24, no hyphens | `stswecs3fullrunagentab12`, `stswecs3aifullrunappab12` |
| Cosmos DB | 44 | `cosmos-swec-s3-ailz-agent-svc-fullrun-ab12` |
| App Configuration | 50 | `appcs-swec-s3-ailz-agent-svc-fullrun-ab12` |
| Container Registry | 50, no hyphens | `crswecs3ailzagentsvcfullrunab12` |
| AI Search | 60 | `srch-swec-s3-ailz-agent-svc-fullrun-app-ab12` |
| Container Apps environment | 60 | `cae-swec-s3-ailz-agent-svc-fullrun-ab12` |
| Log Analytics | 63 | `log-swec-s3-ailz-agent-svc-fullrun-ab12` |
| Foundry account, project | 64 | `aif-swec-s3-ailz-agent-svc-fullrun-ab12`, `proj-swec-s3-ailz-agent-svc-fullrun` |

The Foundry module's own `base_name` (used for its capability host names) is the prefix cut
to 9 characters. Tags and the App Configuration label keep `environment` as written. The
state container stays `tfstate-<env>` with a strict environment name (2 to 20 lowercase
letters, digits or hyphens), because the deploy workflow builds it from the GitHub
environment's name.

## Inputs

| Variable | Default | Meaning |
|---|---|---|
| `location` | `swedencentral` | Region; it must offer the models with quota. |
| `search_location` | `location` | Region of the two AI Search services, for a region without AI Search capacity. Dev uses `norwayeast`. |
| `name_prefix` | `alz` | At least 3 letters or digits; made compliant and shortened per name (see above). |
| `environment` | `dev` | At least 2 letters or digits; part of every name, made compliant like the prefix. |
| `model_deployments` | `gpt-5.4-mini` 2026-03-17, GlobalStandard, 10K TPM | Deployments by name. |
| `project_user_principals` | none | Entra groups that use the project: Foundry User on the account, Log Analytics Reader on Application Insights. |
| `allowed_ip_ranges` | none | Empty means all networks; Entra ID is always required. |
| `log_analytics_retention_days` | 30 | 30 to 730. |
| `tags` | none | Added to the `workload` and `environment` tags. |
| `enable_telemetry` | `false` | AVM usage telemetry. |
| `deploy_agent_service_dependencies` | `true` | Standard agent setup (on) or basic setup (off). |
| `existing_agent_service_dependencies` | none | Resource IDs of an existing dedicated Cosmos DB, AI Search and Storage to connect instead of creating them. |
| `agent_cosmos_db_serverless` | `true` | Serverless Cosmos DB; off: provisioned, with `agent_cosmos_db_total_throughput_limit` (-1 or at least 3000 RU/s). |
| `agent_search_sku`, `agent_search_replica_count` | `basic`, 1 | AI Search for the Agent Service. |
| `deploy_workload` | `true` | The workload group: App Configuration, Container Registry, Container Apps environment, applications' identity, Key Vault, the applications' AI Search and Storage (decision D2). |
| `app_configuration_sku`, `container_registry_sku`, `app_search_sku` | `standard`, `Basic`, `basic` | SKUs of the workload resources. |

`deploy_application_platform` and `deploy_application_data` are replaced by `deploy_workload`.
A tfvars file that still sets either one fails the plan with a message saying so.

**Existing environments:** the regrouping changes no resource. Key Vault and its diagnostic
setting moved from the old core group into the workload, so `moved` blocks in
`main.workload.tf` carry them to their new addresses: the first plan shows them as moved, not
replaced. Turning `deploy_workload` off deletes Key Vault too; with purge protection, it stays
soft-deleted for 90 days under its name.

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

With the workload on, Terraform writes these keys, labeled with the environment (`dev`),
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
| `landingzone:app_data:search_endpoint`, `landingzone:app_data:blob_endpoint` | The applications' AI Search and Blob endpoints |

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
