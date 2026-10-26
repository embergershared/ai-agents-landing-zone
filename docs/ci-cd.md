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
| Detect stacks | always | .NET when a `*.slnx`/`*.sln`/`*.csproj` is tracked; Python when `requirements-dev.lock` or `requirements.lock` is. |
| Workflow lint | always | actionlint (checksum-verified download) with shellcheck on every `run:` script. |
| Package age gate | .NET or Python | `scripts/check_package_age.py`: every locked version at least 7 days old (see [supply-chain.md](supply-chain.md)). |
| .NET build and test | .NET | `setup-dotnet` from `global.json`, NuGet cache, restore in locked mode, `dotnet format --verify-no-changes`, Release build, tests with `.trx` results uploaded. |
| Python lint and test | Python | `setup-python` from `.python-version`, `pip install --require-hashes`, `ruff check`, `ruff format --check`, pytest (no tests = warning). |
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

The template has no deploy workflow: each project's target differs. For Azure, start the
infrastructure from [embergershared/azd-private-starter-template](https://github.com/embergershared/azd-private-starter-template),
and write the deploy workflow this way:
- triggered by a green CI run on `main`, or by hand with a version (rollback);
- behind an on/off repository variable and a GitHub environment (with required reviewers for
  anything beyond a sandbox);
- Azure through OIDC (`id-token: write`, `azure/login`, a federated credential on a user-assigned
  managed identity or app registration), IDs from repository or environment variables, never a
  client secret;
- a concurrency group that is never cancelled.

## Private repositories

GitHub Free has no rulesets, required checks, secret scanning or CodeQL for private
repositories. `Initialize-Repo.ps1` says so and skips them. There, the rules still ask for
PRs, and **PR rules** and **CI result** fail visibly on the PR: merge only when both are green.
