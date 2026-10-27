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
| Network | Public endpoint; `allowed_ip_ranges` (empty by default) restricts it to listed ranges. |
| Durability | ZRS by default (`replication_type`). |
| Deletion | `prevent_destroy` on the storage account. |
| Pipeline identity | With `github_deployer`: the user-assigned identity GitHub Actions signs in as (OIDC), with state access and its rights on each environment's scope ([ci-cd.md](ci-cd.md#deploys)). |

The storage account's management-plane properties include its access keys, so they appear
(marked sensitive) in the bootstrap's own state. With shared key access off, those keys
can't be used.

## Bootstrap (once per subscription)

The bootstrap keeps its own small state in a local file **outside the repository working
copy**, so a cleaned-up clone or worktree doesn't lose it. Back that folder up.

PowerShell (workstation), from the repository root:
```powershell
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
$env:ARM_SUBSCRIPTION_ID = az account show --query id -o tsv

Set-Location src/state-backend
$statePath = "$HOME/.terraform-state/ai-agents-landing-zone/state-backend/terraform.tfstate"
terraform init -backend-config="path=$statePath"

# Optional: copy terraform.tfvars.example to terraform.tfvars (gitignored) and adjust it
terraform plan -out bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output backend_config
```

`*.tfplan` files are gitignored: a plan can hold sensitive values. Delete it after the apply.

## Use the backend from a root module

Each environment gets a `<env>.backend.hcl` file built from the `backend_config` output.
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
tag reaches the resource group and the storage account.

## Retire

The storage account has `prevent_destroy`: remove it from the code in a reviewed PR before a
`terraform destroy`, and only after every environment's state has been destroyed or moved.
