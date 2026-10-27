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

Names follow `<abbreviation>-<prefix>-<environment>-<suffix>` (`rg-alz-dev-ab12`,
`aif-alz-dev-ab12`, `kv-alz-dev-ab12`); the project is `proj-<prefix>-<environment>`.

## Inputs

| Variable | Default | Meaning |
|---|---|---|
| `location` | `swedencentral` | Region; it must offer the models with quota. |
| `name_prefix` | `alz` | 3 to 7 lowercase letters or digits. |
| `environment` | `dev` | Part of every name. |
| `model_deployments` | `gpt-5.4-mini` 2026-03-17, GlobalStandard, 10K TPM | Deployments by name. |
| `project_user_principals` | none | Entra groups that use the project (Foundry User role). |
| `allowed_ip_ranges` | none | Empty means all networks; Entra ID is always required. |
| `log_analytics_retention_days` | 30 | 30 to 730. |
| `tags` | none | Added to the `workload` and `environment` tags. |
| `enable_telemetry` | `false` | AVM usage telemetry. |

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

## Known plan noise

- **Foundry diagnostic setting:** every plan shows `log_analytics_destination_type` being set,
  because Azure doesn't keep that value on a Foundry account. This is harmless.
- **Public network access under a policy that turns it off:** in a subscription where Azure
  Policy sets `publicNetworkAccess = Disabled` (see [state-backend.md](state-backend.md)),
  every plan shows Key Vault's `public_network_access_enabled` changing back to `true`, and
  Key Vault refuses calls from outside Azure. A policy that covers only Storage, Key Vault and
  Cosmos DB leaves the Foundry account's public endpoint on.
