# CI/CD

All workflows run on GitHub-hosted `ubuntu-latest` runners: the repository is public, so a
self-hosted runner would run code from fork PRs. Actions are pinned by commit SHA (version in a
comment) and bumped by Dependabot after a 7-day cooldown.

| Workflow | When | What |
|---|---|---|
| **CI** (`ci.yml`) | push to `main`, every PR, by hand | Detects the stacks, then runs the jobs below; **`CI result`** sums them up. |
| **PR rules** (`pr-rules.yml`) | PR opened, edited, updated | Branch name, base branch, linked issue, no AI attribution, commit style (warnings). |
| **CodeQL** (default setup, no file) | push to `main`, every PR, weekly | Code scanning of the languages GitHub detects; results in **Security → Code scanning**. |

## CI jobs

| Job | Runs when | Steps |
|---|---|---|
| Detect stacks | always | Terraform when a `*.tf` is tracked: each folder with one, outside `modules/` and `tests/` folders, is a root module. .NET when a `*.slnx`/`*.sln`/`*.csproj` is tracked; Python when `requirements-dev.lock` or `requirements.lock` is. |
| Workflow lint | always | actionlint (checksum-verified download) with shellcheck on every `run:` script. |
| Terraform checks | Terraform | Terraform `TERRAFORM_VERSION` (workflow `env`), `terraform fmt -check -recursive` once, then in each root module `terraform init -backend=false -lockfile=readonly`, `terraform validate` and `terraform test` (no test files = warning). Every root module reports in the job summary, even after another failed. No Azure sign-in: tests use mocked providers. |
| Package age gate | .NET or Python | `scripts/check_package_age.py`: every locked version at least 7 days old (see [supply-chain.md](supply-chain.md)). |
| .NET build and test | .NET | Kept from the template, skipped here (no .NET project): restore in locked mode, `dotnet format --verify-no-changes`, Release build, tests. It needs the template's .NET SDK and package files back first. |
| Python lint and test | Python | Kept from the template, skipped here (no Python lock file): `pip install --require-hashes`, ruff, pytest. It needs the template's Python version and lock files back first. |
| **CI result** | always | Fails when any job failed or was cancelled; skipped jobs are fine. The check the ruleset requires. |

PR runs cancel the previous run of the same PR; runs on `main` are never cancelled.

## Repository settings

`scripts/Initialize-Repo.ps1` sets these on a public repository. To check them later
(PowerShell):
```powershell
gh api repos/<owner>/<repo>/rulesets --jq '.[].name'
gh api repos/<owner>/<repo> --jq .security_and_analysis
gh api repos/<owner>/<repo>/code-scanning/default-setup --jq .state
```

| Setting | Value |
|---|---|
| Ruleset `main` (default branch) | No deletion, no force push, PR required (0 approvals: one maintainer), checks `CI result` and `PR rules` required |
| Secret scanning, push protection | On: a push with a known secret format is refused |
| Dependabot alerts and security updates | On |
| Private vulnerability reporting | On: see [SECURITY.md](../SECURITY.md) |
| CodeQL | Default setup |
| Issues, wiki, merged branches | Issues on, wiki off, branches deleted on merge |

A new CI job is added to the `needs` of `CI result`, never as a separate required check, so the
ruleset doesn't change.

## Repository variables

| Variable | Default | Used by |
|---|---|---|
| `DOTNET_SOLUTION` | shallowest `*.slnx` / `*.sln` / `*.csproj` | CI |

Set one with `gh variable set DOTNET_SOLUTION --body src/App.slnx --repo <owner>/<repo>`.

## Deploys

There is no deploy workflow yet: phase 5 of the [deployment plan](deployment-plan.md) adds
one (plan on each PR, apply on `main` behind an environment approval). Write it this way:
- triggered by a green CI run on `main`, or by hand with a version (rollback);
- behind an on/off repository variable and a GitHub environment (with required reviewers for
  anything beyond a sandbox);
- Azure through OIDC (`id-token: write`, `azure/login`, a federated credential on a user-assigned
  managed identity or app registration), IDs from repository or environment variables, never a
  client secret; Terraform reads the same identity from `ARM_USE_OIDC`, `ARM_CLIENT_ID`,
  `ARM_TENANT_ID` and `ARM_SUBSCRIPTION_ID` (see `.github/instructions/terraform.instructions.md`);
- a concurrency group that is never cancelled.

## Private repositories

GitHub Free has no rulesets, required checks, secret scanning or CodeQL for private
repositories. `Initialize-Repo.ps1` says so and skips them. There, the rules still ask for
PRs, and **PR rules** and **CI result** fail visibly on the PR: merge only when both are green.
