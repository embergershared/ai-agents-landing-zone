---
applyTo: "**/*.tf,**/*.tftest.hcl,**/*.tfvars.example,**/.terraform.lock.hcl"
---

# Terraform

- **Layout:** each root module is a folder under `src/` (`src/state-backend/`,
  `src/landing-zone/`), with `terraform test` files in its `tests/` folder. CI treats every
  folder with a `*.tf` file, outside `modules/` and `tests/` folders, as a root module.
- **Pin versions.** `required_version` with a lower and an upper bound
  (`">= 1.12, < 2.0"`); each provider in `required_providers` with a pessimistic constraint
  (`~> 4.38`); each registry module with an exact `version` (`"0.12.0"`). Only releases at
  least 7 days old (Terraform, providers and modules alike); Dependabot (`terraform`, 7-day
  cooldown) proposes the bumps.
- **Commit the lock file.** `.terraform.lock.hcl` is committed next to each root module, with
  hashes for every platform that runs it:
  `terraform providers lock -platform=linux_amd64 -platform=windows_amd64 -platform=darwin_arm64`.
  CI runs `terraform init -lockfile=readonly`, which fails when the lock file is missing or out
  of date.
- **No secrets in state, outputs or `tfvars`.** State is stored in plain text: never put a key,
  password or connection string in a variable default, a `tfvars` file or an output, and
  prefer Entra ID authentication so there is none to store. A value that must pass through
  Terraform is `sensitive = true` and comes from an environment variable (`TF_VAR_<name>`) or
  Key Vault. `*.tfvars` files are gitignored; commit a `*.tfvars.example` with placeholders.
- **No real identifiers in code:** tenant, subscription and principal IDs come from variables
  or the environment (`ARM_SUBSCRIPTION_ID`), never from a committed file.
- **Before each commit:** `terraform fmt -recursive`, then `terraform validate` and
  `terraform test` in each changed root module. CI runs `fmt -check -recursive`,
  `init -backend=false`, `validate` and `test` on every PR.
- **Tests run offline.** `terraform test` files use `mock_provider` (or `override_resource`),
  so they need no Azure sign-in and create nothing; CI has no Azure credentials for them.
- **Sign-in through OIDC in pipelines.** The azurerm provider and backend use workload identity
  federation: `ARM_USE_OIDC=true`, with `ARM_CLIENT_ID`, `ARM_TENANT_ID` and
  `ARM_SUBSCRIPTION_ID` from repository or environment variables, and `id-token: write` on
  the job. Never a client secret or a storage access key. Locally, sign in with `az login`.
- **Entra ID for storage:** `storage_use_azuread = true` in the azurerm `provider` block, and
  `use_azuread_auth = true` in the `azurerm` backend, so neither needs a storage account key
  and every storage account keeps `shared_access_key_enabled = false`.
- **Plan before apply.** Read every `terraform plan` before applying it, look for replaced or
  destroyed resources, and apply only after an explicit go-ahead (see *Safety* in
  `.github/copilot-instructions.md`).
