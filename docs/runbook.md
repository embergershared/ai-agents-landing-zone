# Runbook: deploy, check, change and retire an environment

This page is for someone deploying the Agent Landing Zone who didn't write it. The details
behind each step are in [state-backend.md](state-backend.md), [landing-zone.md](landing-zone.md)
and [ci-cd.md](ci-cd.md). Commands are PowerShell on a workstation, run from the repository
root unless a step says otherwise.

## 1. Prerequisites

| What | Check |
|---|---|
| **Tools** | Terraform 1.12 or later (CI uses 1.16.6), Azure CLI, GitHub CLI. `terraform version`, `az version`, `gh --version`. |
| **Rights for the first deploy** | Owner on the subscription, or Contributor plus Role Based Access Control Administrator. The first deploy creates resource groups, registers resource providers and assigns roles. Later changes can go through the pipeline identity, whose rights are limited to the environment's resource group ([ci-cd.md](ci-cd.md#deploys)). |
| **Resource providers** | `Microsoft.CognitiveServices`, `Microsoft.DocumentDB`, `Microsoft.Search`, `Microsoft.Storage`, `Microsoft.KeyVault`, `Microsoft.OperationalInsights`, `Microsoft.Insights`, `Microsoft.AppConfiguration`, `Microsoft.ContainerRegistry`, `Microsoft.App`, `Microsoft.ManagedIdentity`. The azurerm provider registers the missing ones on the owner's first plan. Check them with `az provider list --query "[?registrationState=='Registered'].namespace" -o tsv`. |
| **Model quota** | `az cognitiveservices usage list -l <region> --query "[?contains(name.value,'GlobalStandard.gpt-5.4-mini')]"`: the limit (thousands of tokens per minute) minus current use covers each deployment's `capacity`. |
| **AI Search quota and capacity** | Quota: `az rest --method get --url "https://management.azure.com/subscriptions/<subscription-id>/providers/Microsoft.Search/locations/<region>/usages?api-version=2025-05-01"`. You need one service for the applications' data and one for the Agent Service when its switch is on. Quota isn't capacity: a region can still answer `InsufficientResourcesAvailable` (see [Troubleshooting](#6-troubleshooting)). |
| **Policies** | An Azure Policy that turns off public network access on Storage, Key Vault or Cosmos DB blocks the state backend and the Agent Service's standard setup. Check before you start (see [Troubleshooting](#6-troubleshooting)). |
| **Entra group** | The object ID of the group whose members use the Foundry project (`project_user_principals`). |

Sign in:
```powershell
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
$env:ARM_SUBSCRIPTION_ID = az account show --query id -o tsv
az account show --query "{subscription:name, tenant:tenantId, user:user.name}" -o table
```

## 2. Deploy

### 2.1 State backend (once per environment)

Each environment needs its state container. The script reads `location`, `name_prefix`, `tags`
and `allowed_ip_ranges` from the environment's `environments/<env>.tfvars`, creates or updates
the backend for that `name_prefix` with a `tfstate-<env>` container, and writes
`environments/<env>.backend.hcl`. Environments with the same `name_prefix` share one backend.

```powershell
$envName = 'dev'
./scripts/New-StateBackend.ps1 -Environment $envName -PlanOnly   # dry run: shows the plan, changes nothing
./scripts/New-StateBackend.ps1 -Environment $envName             # asks before it applies
```

It stops before applying when the plan would delete or replace anything, and fails when the
storage account's public network access is off. The pipeline identity (`github_deployer`) and
the other bootstrap-only values still come from `src/state-backend/terraform.tfvars`
(gitignored, copied from its `.example`). The manual commands are in
[state-backend.md](state-backend.md#bootstrap-once-per-subscription-and-name-prefix).

Back up the folder that holds the bootstrap states (`$HOME/.terraform-state/...`).

### 2.2 The environment

The commands use `$envName`; set it to the environment (`dev`, `test`, ...).

```powershell
Set-Location src/landing-zone
$envName = 'dev'
# environments/<env>.tfvars holds the committed values. For a new environment, copy dev.tfvars,
# set environment = "<env>", and review region, search_location, switches and tags.
# <env>.backend.hcl (gitignored) was written by scripts/New-StateBackend.ps1 (2.1).
# -reconfigure: needed when this folder was initialized for another environment before
terraform init -reconfigure -backend-config="environments/$envName.backend.hcl"
$env:TF_VAR_project_user_principals = '{"users":{"principal_id":"<entra-group-object-id>","principal_type":"Group"}}'
# You write the App Configuration settings: list yourself (az ad signed-in-user show --query id -o tsv)
$env:TF_VAR_app_settings_writer_principals = '{"me":{"principal_id":"<your-entra-object-id>","principal_type":"User"}}'
terraform plan -var-file="environments/$envName.tfvars" -out "$envName.tfplan"
```

Read the plan before you apply it. A first deploy only adds resources. Any "destroy" or "must be
replaced" line needs a reason. Then:
```powershell
terraform apply "$envName.tfplan"
Remove-Item "$envName.tfplan"
```

A full environment takes about 15 minutes (the Foundry module waits 5 minutes for the account).

### 2.3 Pipeline (optional)

Set `github_deployer` in the bootstrap's `terraform.tfvars` and apply it again (2.1), then set the
repository secrets ([ci-cd.md](ci-cd.md#repository-secrets)) and turn the workflow on
([ci-cd.md](ci-cd.md#turn-it-on)).

## 3. Verify

| Check | How | Expected |
|---|---|---|
| The model answers with Entra ID only | [landing-zone.md, Verify](landing-zone.md#verify-a-model-call-with-an-entra-id-token) | The reply text; an `api-key` call gets 401 |
| An agent runs | [landing-zone.md, agent check](landing-zone.md#the-agent-service-dependencies-switch) | The run completes and the thread holds the answer |
| Standard setup (switch on) | After an agent run: `az cosmosdb sql database list -a <cosmos-name> -g <rg> --query "[].name"` | The Agent Service's databases exist in our Cosmos DB |
| Applications read their settings | A Container Apps job as the applications' identity runs `az appconfig kv list --endpoint <endpoint> --auth-mode login --label <env>` ([landing-zone.md](landing-zone.md#settings-in-app-configuration)) | Every `landingzone:` key |
| Diagnostics | `az monitor diagnostic-settings list --resource <resource-id> --query "[].name"` on Foundry, Key Vault, App Configuration, Container Apps, AI Search | `to-log-analytics` |
| No drift | `terraform plan -var-file=environments/<env>.tfvars` | Only the known plan noise ([landing-zone.md](landing-zone.md#known-plan-noise)) |

## 4. Change

1. Change `environments/<env>.tfvars` or the code on a branch. A PR shows the plan when the
   pipeline is on; otherwise run `terraform plan` yourself.
2. Merge the PR once **CI result** and **PR rules** are green.
3. Apply: **Actions → Terraform deploy → Run workflow** (`plan`, then `apply`), or
   `terraform plan -out` and `terraform apply` from a workstation.

Common changes:
- **A model:** add or change it in `model_deployments` (check the quota first). Applications
  read the names from `landingzone:foundry:models`.
- **The Agent Service setup:** `deploy_agent_service_dependencies`. Turning it off destroys the
  Agent Service's Cosmos DB, AI Search and Storage, and the agents' threads and files in them.
  Export what you need first.
- **The workload:** `deploy_workload`. Turning it off destroys App Configuration, the Container
  Registry and its images, the Container Apps environment, the applications' identity, Key Vault
  (soft-deleted for 90 days) and the applications' AI Search and Storage with their data.
  Export what you need first.
- **IP allow lists:** `allowed_ip_ranges` applies to every service at once.
- **Provider, module or Terraform versions:** Dependabot opens the PRs (7-day cooldown).
  Terraform in CI is `TERRAFORM_VERSION` in both workflows ([supply-chain.md](supply-chain.md)).

## 5. Retire an environment

1. Export what must be kept: agent threads (Cosmos DB), files (Storage), App Configuration
   settings, logs.
2. Delete what Azure created by itself in the resource group. Terraform won't delete a resource
   group that still holds resources it doesn't manage (`prevent_deletion_if_contains_resources`).
   Application Insights always adds a "Failure Anomalies" smart detector alert rule:
   ```powershell
   az resource list -g <rg> --resource-type microsoft.alertsmanagement/smartDetectorAlertRules --query "[].id" -o tsv |
     ForEach-Object { az resource delete --ids $_ }
   ```
   List what else is there (`az resource list -g <rg> -o table`); anything not in the destroy
   plan needs a decision first.
3. Destroy, from `src/landing-zone` with the environment's backend (about 40 minutes):
   ```powershell
   terraform plan -destroy -var-file=environments/<env>.tfvars -out destroy.tfplan
   # Check the plan names only this environment's resource group
   terraform apply destroy.tfplan
   ```
4. Purge soft-deleted resources that would block a redeploy with the same name, or keep
   charging:
   ```powershell
   # Foundry (AI Services) account: soft-deleted for 48 hours
   az cognitiveservices account list-deleted --query "[].{name:name, location:location}" -o table
   az cognitiveservices account purge --name <aif-name> --resource-group <rg> --location <region>
   # App Configuration store
   az appconfig list-deleted --query "[].{name:name, location:location}" -o table
   az appconfig purge --name <appcs-name> --location <region>
   ```
   Key Vault has purge protection: it stays soft-deleted for 90 days and can't be purged. Its
   name has a random suffix, so a redeploy doesn't collide with it.
5. Remove the environment from the pipeline: its `github_deployer.environments` entry (apply the
   bootstrap again), its `PROJECT_USER_PRINCIPALS_<ENV>` and `APP_SETTINGS_WRITERS_<ENV>`
   secrets, its GitHub environment, and its state container (a manual bootstrap run without
   it in `environments`: [state-backend.md](state-backend.md#remove-an-environments-container)).

Retire the state backend only after every environment is gone ([state-backend.md](state-backend.md#retire)).

## 6. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `terraform init` gets `403 AuthorizationFailure` from the state account, and the plan shows `public_network_access_enabled: false -> true` | An Azure Policy turns off public network access. See [state-backend.md](state-backend.md#subscriptions-with-a-policy-that-turns-off-public-network-access). The same policy blocks Key Vault, the Agent Service's standard setup (Cosmos DB, Storage) and the applications' Storage from outside Azure. |
| `InsufficientResourcesAvailable` when creating AI Search | The region has no capacity right now, whatever the quota (on 2026-10-27, Sweden Central and East US 2 had none for Basic or Standard). Apply again later, or set `search_location` to a nearby region that has capacity: dev uses `norwayeast`. Only a create shows capacity; a throwaway service in its own resource group, deleted afterwards, tests a region. |
| `AADSTS700213: No matching federated identity record` in the deploy workflow | The repository sends immutable OIDC subjects: set `github_deployer.subject_prefix` ([ci-cd.md](ci-cd.md#deploys)). |
| `AuthorizationFailed` writing a role assignment from the pipeline | The landing zone grants a role that isn't in `deployer_assignable_role_ids`. Add it, and apply the bootstrap. |
| 403 on App Configuration keys ("while checking for key ... existence"), in a plan or right after an apply | The caller's App Configuration Data Owner role hasn't reached the data plane yet. It took about 40 minutes for a new pipeline identity here, with calls failing and passing in turns meanwhile. Wait, then run again. People running Terraform from a workstation must be in `app_settings_writer_principals`. |
| Azure CLI: `Continuous access evaluation ... InteractionRequired` | The sign-in is too old for Microsoft Graph. Run `az login` again. Terraform's management calls don't need Graph. |
| Every plan changes `log_analytics_destination_type` on Foundry's diagnostic setting | Known and harmless ([landing-zone.md](landing-zone.md#known-plan-noise)). |

## 7. Cost per environment

These are monthly list prices in Sweden Central, in USD, for 730 hours, from the
[Azure retail prices API](https://prices.azure.com/api/retail/prices) on 2026-10-27. They
include no discounts or taxes. Usage-based items depend on traffic.

| Resource | Price | dev (Agent Service off) | Agent Service on: add |
|---|---|---|---|
| AI Search, Basic, 1 replica | $0.101/hour | $73.73 (applications' data) | $73.73 |
| App Configuration, Standard | $1.20/day | $36.50 | |
| Container Registry, Basic | $0.1666/day, plus $0.10/GB above the included storage | $5.07 | |
| Log Analytics (with Application Insights) | First 5 GB/month free, then $2.99/GB | $0 to $15 | a few GB more |
| Key Vault, Standard | $0.03 per 10,000 operations | under $1 | |
| Storage, ZRS Hot (applications' data, state) | $0.023/GB-month, plus transactions | under $1 | under $1 |
| Cosmos DB, serverless | Request units used, plus $0.25/GB-month | | under $5 for light use |
| Container Apps, Consumption | Per vCPU-second and GiB-second, with a monthly free grant; nothing when idle | $0 idle | |
| Foundry account and project | No fixed charge | $0 | |
| gpt-5.4-mini, Global Standard | $0.75 per million input tokens, $4.50 per million output tokens | usage | usage |
| **Fixed part, idle** | | **about $116** | **about $75 more** |

A production environment with 2 or more AI Search replicas (for the read SLA), Standard
App Configuration replicas, or provisioned Cosmos DB throughput (at least 3000 RU/s) costs
more. Price it with the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/)
before choosing those values.

## 8. Last full run

On 2026-10-27, a fresh environment (`rbook`) was deployed, verified and retired by following
this runbook only, from a fresh clone of `main`, in the dev subscription:

| Step | Seen |
|---|---|
| 2.1 | `environments = ["dev", "rbook"]`: 1 container added. |
| 2.2 | Plan: 57 to add, 0 to change, 0 to destroy. Apply: 57 added in 16 minutes. |
| 3. Verify | Model call answered ("landing zone ok"), and an `api-key` call got 401. An agent run completed ("agents work"), and the Agent Service created its database and containers in our Cosmos DB. A Container Apps job as the applications' identity listed every `landingzone:` key. `to-log-analytics` is on Foundry, Key Vault, App Configuration, Container Apps, Cosmos DB and both AI Search services. Plan: only the known Foundry diagnostics diff. |
| 5. Retire | The destroy (57 resources, 38 minutes) stopped at the resource group because of the "Failure Anomalies" alert rule: deleted, destroy finished. Foundry account and App Configuration store purged; Key Vault kept by purge protection. Container removed from the bootstrap (1 destroyed). Dev unchanged. |

The gaps it found are fixed above: environment-specific commands, `-reconfigure`, a new
environment's state container, and the alert rule that blocks the resource group's deletion.
