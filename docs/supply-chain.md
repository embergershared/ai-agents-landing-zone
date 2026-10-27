# Package sources and the age gate

Two rules, from the repository rules:
1. **Approved source only.** Terraform providers and modules from the Terraform registry
   (`registry.terraform.io`). Never a second source next to it as a fallback: fail closed.
   Where the registry can't be reached, switch the source instead (see
   [Turn the approved feed off](#turn-the-approved-feed-off)).
2. **7-day age gate.** A Terraform, provider or module version, or a GitHub Action release, is
   used only once it has been public for at least 7 days.

## How each ecosystem follows them

| Ecosystem | Pinned in | Age gate | Integrity |
|---|---|---|---|
| Terraform CLI | `TERRAFORM_VERSION` in `.github/workflows/ci.yml`; `required_version` in each root module | By hand: check the release date on [GitHub](https://github.com/hashicorp/terraform/releases) | `hashicorp/setup-terraform` downloads from releases.hashicorp.com |
| Terraform providers | `required_providers` (`~>` constraint) and `.terraform.lock.hcl` per root module | Dependabot `terraform` with `cooldown: default-days: 7`; by hand when adding one | Provider hashes in the lock file; CI runs `terraform init -lockfile=readonly` |
| Terraform modules | Exact `version` on each registry `module` block | Dependabot `terraform` with `cooldown: default-days: 7`; by hand when adding one | The exact version |
| GitHub Actions | commit SHA in each `uses:` | Dependabot `cooldown: default-days: 7` | the SHA |

## Update a provider or module

PowerShell, in the root module's folder (e.g. `src/landing-zone`):
```powershell
# 1. Change the version constraint (a release at least 7 days old: check its date on the
#    registry page of the provider or module)
terraform init -upgrade -backend=false
# 2. Record the hashes for every platform that runs this module, then commit the lock file
terraform providers lock -platform=linux_amd64 -platform=windows_amd64 -platform=darwin_arm64
terraform validate
terraform test
```

Dependabot's `terraform` PRs update the constraint and the lock file together, at least
7 days after the release.

## Major versions held back

| Provider | Stays on | Why |
|---|---|---|
| `hashicorp/azurerm` | 4.x, in every root module | The Foundry module (`Azure/avm-ptn-aiml-ai-foundry`) needs `azurerm ~> 4.38`, and both root modules stay on the same major version |

Dependabot ignores the major-version updates of these providers (`ignore` in
`.github/dependabot.yml`); minor and patch updates keep coming. Move to a new major version
by hand, through its own issue, in every root module at once, once the modules it uses
support it; then remove the `ignore` entry.

## When a release is too new

Pick the previous release, or wait until it is 7 days old. For an urgent fix that can't wait
(a security patch), say why in the PR, and in the issue it links, with the date the gate would
have allowed it.

## Turn the approved feed off

Where the Terraform registry can't be reached directly (a customer or a contributor behind a
proxy), switch the source, don't add a second one: in your Terraform CLI configuration
(`.terraformrc`, gitignored), a `provider_installation` block with your organization's network
mirror replaces direct registry access. Keep the lock file: its hashes don't depend on the
source.

The age gate and the hashes don't depend on the source. In this repository, commit a source
change through its issue and PR, and say why in the PR; in a fork, keep it local.
