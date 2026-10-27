# CI/CD

All workflows run on GitHub-hosted `ubuntu-latest` runners: the repository is public, so a
self-hosted runner would run code from fork PRs. Actions are pinned by commit SHA (version in a
comment) and bumped by Dependabot after a 7-day cooldown.

| Workflow | When | What |
|---|---|---|
| **CI** (`ci.yml`) | push to `main`, every PR, by hand | Detects the stacks, then runs the jobs below; **`CI result`** sums them up. |
| **PR rules** (`pr-rules.yml`) | PR opened, edited, updated | Branch name, base branch, linked issue, no AI attribution, commit style (warnings). |
| **Terraform deploy** (`terraform-deploy.yml`) | PR changing `src/landing-zone/`, by hand from `main` | Plans each environment on a PR; plans or applies one environment by hand. Off until `TF_DEPLOY_ENABLED` is `true`. See [Deploys](#deploys). |
| **CodeQL** (default setup, no file) | push to `main`, every PR, weekly | Code scanning of the languages GitHub detects; results in **Security → Code scanning**. |

## CI jobs

| Job | Runs when | Steps |
|---|---|---|
| Detect stacks | always | Terraform when a `*.tf` is tracked: each folder with one, outside `modules/` and `tests/` folders, is a root module. .NET when a `*.slnx`/`*.sln`/`*.csproj` is tracked; Python when `requirements-dev.lock` or `requirements.lock` is. |
| Workflow lint | always | actionlint (checksum-verified download) with shellcheck on every `run:` script. |
| Terraform checks | Terraform | Terraform `TERRAFORM_VERSION` (workflow `env`), `terraform fmt -check -recursive` once, then in each root module `terraform init -backend=false -lockfile=readonly`, `terraform validate` and `terraform test` (no test files = warning). Every root module reports in the job summary, even after another failed. No Azure sign-in: tests use mocked providers. |
| Package age gate | .NET or Python | Kept from the template, skipped here (no NuGet or Python lock file): `scripts/check_package_age.py` checks every locked version is at least 7 days old. |
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
| Private vulnerability reporting | On: see [SECURITY.md](SECURITY.md) |
| CodeQL | Default setup |
| Issues, wiki, merged branches | Issues on, wiki off, branches deleted on merge |

A new CI job is added to the `needs` of `CI result`, never as a separate required check, so the
ruleset doesn't change.

## Repository variables

| Variable | Default | Used by |
|---|---|---|
| `DOTNET_SOLUTION` | shallowest `*.slnx` / `*.sln` / `*.csproj` | CI |
| `TF_DEPLOY_ENABLED` | not `true`: off | Terraform deploy: on/off switch |
| `AZURE_CLIENT_ID` | none | Terraform deploy: client ID of the pipeline identity (`github_deployer` output of `src/state-backend`) |
| `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | none | Terraform deploy: where it signs in and deploys |
| `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT` | none | Terraform deploy: the state backend (`backend_config` output) |
| `PROJECT_USER_PRINCIPALS_<ENV>` | `{}` | Terraform deploy: `project_user_principals` of that environment, as JSON (Entra object IDs stay out of the repository) |
| `APP_SETTINGS_WRITERS_<ENV>` | `{}` | Terraform deploy: `app_settings_writer_principals` of that environment, as JSON: the people who also run Terraform from a workstation |

Set one with `gh variable set DOTNET_SOLUTION --body src/App.slnx --repo <owner>/<repo>`.

## Deploys

`terraform-deploy.yml` deploys `src/landing-zone/` with the values in
`src/landing-zone/environments/<env>.tfvars` and the state in the `tfstate-<env>` container.

| Trigger | Job | Identity (OIDC subject) |
|---|---|---|
| PR that changes `src/landing-zone/` | **Plan** for each environment, shown in the job summary | `repo:<owner>/<repo>:pull_request` |
| By hand (**Run workflow**) on `main`, with an environment and `plan` or `apply` | **Plan**, then **apply** of that plan when `apply` was chosen | `repo:<owner>/<repo>:environment:<env>` |

- **Sign-in:** the user-assigned identity `id-<prefix>-github-deployer` from `src/state-backend`
  (`github_deployer`), with federated credentials for the two subjects above. A repository
  with immutable OIDC subjects sends `repo:<owner>@<owner-id>/<repo>@<repo-id>` as the prefix:
  set it in `github_deployer.subject_prefix`, as
  `gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix` reports it. Terraform reads
  `ARM_USE_OIDC`, `ARM_CLIENT_ID`, `ARM_TENANT_ID` and `ARM_SUBSCRIPTION_ID`; no client secret
  exists.
- **Rights, per environment scope** (the environment's resource group): Contributor, and Role
  Based Access Control Administrator with a condition that allows only the roles the landing
  zone grants (`deployer_assignable_role_ids`). The identity can't grant Contributor or Owner.
  It also has App Configuration Data Owner on that scope (a plan reads the settings through the
  data plane, so the role must exist before its first plan) and Storage Blob Data Contributor on
  the state account. It doesn't register resource
  providers (`ARM_RESOURCE_PROVIDER_REGISTRATIONS=none`): the owner's first deploy does.
- **Approval:** the GitHub environment `<env>` accepts deployments from `main` only. Required
  reviewers need a paid GitHub plan for a private repository, so the approval is starting
  the workflow by hand. On a public repository or a paid plan, add required reviewers to the
  environment.
- **Pull requests** sign in with the same identity, so its rights reach code in any PR branch.
  That is acceptable while only the owner can push. With more contributors, give PR plans a
  second identity with Reader and state access only.
- **Never cancelled:** the concurrency group doesn't cancel a run in progress.

### Turn it on

1. The state backend accepts the pipeline (public network access on the state account; see
   [state-backend.md](state-backend.md)).
2. The environment's state is in its container. If it was deployed from a workstation with a
   local state, move it once, from `src/landing-zone` (PowerShell):
   `terraform init -migrate-state -backend-config=environments/dev.backend.hcl`.
3. `gh variable set TF_DEPLOY_ENABLED --body true --repo <owner>/<repo>`.
4. **Actions → Terraform deploy → Run workflow**, environment `dev`, action `plan`. Read the
   plan, then run it again with `apply`.

## Private repositories

GitHub Free has no rulesets, required checks, secret scanning or CodeQL for private
repositories. `Initialize-Repo.ps1` says so and skips them. There, the rules still ask for
PRs, and **PR rules** and **CI result** fail visibly on the PR: merge only when both are green.
