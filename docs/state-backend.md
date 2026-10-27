# Terraform state backend

The landing zone's state lives in an Azure Storage account that `src/state-backend/` creates
once. One container per environment (`tfstate-<env>`) holds that environment's state blob.

| Property | Setting |
|---|---|
| Authentication | Entra ID only: shared key access off, SFTP local users off, OAuth by default, no anonymous access. Terraform uses `use_azuread_auth = true`. |
| Access | `Storage Blob Data Contributor` on the account for the identity running the bootstrap and for `state_contributor_principal_ids` (the pipeline identity, a deployer group). |
| Locking | Blob leases, built into the `azurerm` backend. |
| Recovery | Blob versioning, and soft delete of blobs and containers (`soft_delete_retention_days`, 30 by default). |
| Transport | HTTPS only, TLS 1.2 minimum. |
| Network | Public endpoint; `allowed_ip_ranges` (empty by default) restricts it to listed ranges. With none, the account has no network rules block (all networks): the provider reads an explicit allow-all rule set back as absent. |
| Durability | ZRS by default (`replication_type`). |
| Deletion | `prevent_destroy` on the storage account. |
| Pipeline identity | With `github_deployer`: the user-assigned identity GitHub Actions signs in as (OIDC), with state access and its rights on each environment's scope ([ci-cd.md](ci-cd.md#deploys)). |

The storage account's management-plane properties include its access keys, so they appear
(marked sensitive) in the bootstrap's own state. With shared key access off, those keys
can't be used.

## Bootstrap (once per subscription and name prefix)

One backend serves every environment with the same `name_prefix` in a subscription; each
environment adds its `tfstate-<env>` container. The bootstrap keeps its own small state in a
local file **outside the repository working copy**, one per subscription and name prefix, so a
cleaned-up clone or worktree doesn't lose it, and a second prefix never replaces the first one's
backend. Back that folder up:
```
$HOME/.terraform-state/ai-agents-landing-zone/state-backend/<subscription-id>/<name_prefix>/terraform.tfstate
```

### With the script

`scripts/New-StateBackend.ps1` deploys an environment's backend from the environment's own
`src/landing-zone/environments/<env>.tfvars`, so both use the same values. PowerShell
(workstation), from the repository root, signed in to the target subscription:
```powershell
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
./scripts/New-StateBackend.ps1 -Environment dev -PlanOnly   # dry run
./scripts/New-StateBackend.ps1 -Environment dev
```

| Step | What it does |
|---|---|
| Inputs | Reads `environment` and `name_prefix` from `<env>.tfvars`; the file name and `environment` must match. |
| Init | Uses the subscription and prefix's bootstrap state. It stops when a deployed backend is still in the older single state file (`state-backend/terraform.tfstate`) and gives the command that moves it. |
| Plan | Passes `<env>.tfvars` to the bootstrap (`location`, `name_prefix`, `tags`, `allowed_ip_ranges`; Terraform warns about the variables the bootstrap doesn't declare) and sets `environments` to the containers already there plus this one. Values that only the bootstrap has, such as `github_deployer` or `replication_type`, still come from `src/state-backend/terraform.tfvars`. |
| Guard | Stops when the plan deletes or replaces anything: environments sharing a backend must agree on `location`, and their `tags` are the backend's tags. |
| Apply | Asks first, unless `-AutoApprove`; `-PlanOnly` stops before. |
| Check | Fails when the storage account's `publicNetworkAccess` isn't `Enabled` (see the policy section below). |
| Output | Writes `environments/<env>.backend.hcl` from `backend_config`. |

The resource group and storage account keep their random suffix (`rg-<prefix>-tfstate-<suffix>`,
`st<prefix>tfstate<suffix>`): storage account names are global, and a new backend never reuses
a retired one's name. The names are made compliant from `name_prefix` as in the landing zone
([landing-zone.md](landing-zone.md#compliant-names-from-any-prefix-and-environment)): lowercase,
other characters as single hyphens, and the prefix shortened to fit (resource group 90
characters, storage account 24 without hyphens). `swec-s3-ailz-agent-svc` gives
`rg-swec-s3-ailz-agent-svc-tfstate-<suffix>` and `stswecs3ailzatfstate<suffix>`. The bootstrap
state's folder uses the same compliant prefix.

### By hand

PowerShell (workstation), from the repository root:
```powershell
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
$env:ARM_SUBSCRIPTION_ID = az account show --query id -o tsv

Set-Location src/state-backend
$statePath = "$HOME/.terraform-state/ai-agents-landing-zone/state-backend/$env:ARM_SUBSCRIPTION_ID/<name_prefix>/terraform.tfstate"
terraform init -reconfigure -backend-config="path=$statePath"

# Copy terraform.tfvars.example to terraform.tfvars (gitignored) and set environments, tags, ...
terraform plan -out bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output backend_config
```

`*.tfplan` files are gitignored: a plan can hold sensitive values. Delete it after the apply.

### Remove an environment's container

The script only adds containers. To remove one, run the bootstrap by hand with `environments`
set to the ones that stay, after that environment's state has been destroyed or moved:
```powershell
terraform plan -var='environments=["dev"]' -out bootstrap.tfplan
```
The container has soft delete: it can be restored for `soft_delete_retention_days`.

## Use the backend from a root module

Each environment gets a `<env>.backend.hcl` file built from the `backend_config` output (the
script writes it).
It holds the real resource names, so it is gitignored; the committed
`<env>.backend.hcl.example` shows its shape:
```hcl
resource_group_name  = "rg-<prefix>-tfstate-<suffix>"
storage_account_name = "st<prefix>tfstate<suffix>"
container_name       = "tfstate-<env>"
key                  = "landing-zone.tfstate"
use_azuread_auth     = true
```

The root module declares an empty `backend "azurerm" {}` block and is initialized with:
```powershell
terraform init -backend-config=environments/dev.backend.hcl
```

A pipeline passes the same values with `-backend-config="key=value"` arguments from
repository or environment variables, and signs in through OIDC (`ARM_USE_OIDC=true`).

## Subscriptions with a policy that turns off public network access

Some organizations assign an Azure Policy that sets `publicNetworkAccess = Disabled` on new
storage accounts (and on Key Vault and Cosmos DB accounts). The bootstrap still succeeds, but
the account then refuses every request from outside Azure (403 `AuthorizationFailure`), and
every later `terraform plan` shows `public_network_access_enabled` changing back to `true`.

Check the account after the apply:
```powershell
az storage account show -n <storage-account-name> --query publicNetworkAccess -o tsv
```

If it shows `Disabled`, find the policy in the resource group's activity log
(`Microsoft.Authorization/policies/modify/action`). Read its rule for the exemption it
supports, such as a tag on the resource or resource group, or a Network Security Perimeter.
Whether to use that exemption is a decision for the subscription's owner. If the answer is
yes and the exemption is a tag, set it in `tags` (`terraform.tfvars`) and apply again. The
tag reaches the resource group and the storage account, and Terraform turns public access back
on in the same apply. Do the same for each environment (`tags` in `environments/<env>.tfvars`),
because the policy also covers the landing zone's Key Vault, Cosmos DB and Storage.

This repository's dev subscription uses the tag exemption (`SecurityControl = Ignore`, owner's
decision of 2026-10-27).

## Retire

The storage account has `prevent_destroy`: remove it from the code in a reviewed PR before a
`terraform destroy`, and only after every environment's state has been destroyed or moved.
