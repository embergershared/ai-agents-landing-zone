# Changelog

What changed for users of ai-agents-landing-zone, newest first. Each merged PR adds its line under
**Unreleased** (with its issue number); a release moves them under a dated version.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added
- Repository created from [embergershared/repo-template](https://github.com/embergershared/repo-template).
- README explains the Agent Landing Zone, its Bicep and Terraform implementations and their limits (#3).
- Deployment plan for the Agent Landing Zone with Terraform on public endpoints, without AI Gateway, with a switch
  for the Foundry Agent Service dependencies (#3).
- Terraform tooling: ignore rules for state, `*.tfvars` and `.terraform/`, a CI job that runs `terraform fmt`,
  `validate` and `test` in each root module, Dependabot updates and agent rules for Terraform (#6).
- Terraform state backend: `src/state-backend/` creates an Entra ID-only storage account with versioning, soft delete
  and one state container per environment; `docs/state-backend.md` explains the bootstrap and the backend settings (#7).
- Landing zone root module: `src/landing-zone/` deploys the core resources (Log Analytics, Application Insights, Key Vault)
  and a Foundry account, project and `gpt-5.4-mini` deployment on public endpoints with key authentication off (#8).
- Agent Service dependencies switch: `deploy_agent_service_dependencies` deploys the standard agent setup (Cosmos DB,
  AI Search, Storage, connections, capability hosts, RBAC), reuses an existing set, or keeps the basic setup (#9).
- Application platform and data: App Configuration with the landing zone's endpoints, Container Registry, Container Apps
  environment, the applications' managed identity, and their own AI Search and Storage, each behind a switch (#10).
- Deployment pipeline: `environments/dev.tfvars`, a GitHub Actions workflow that plans each environment on PRs and
  plans or applies one by hand from `main`, signing in through OIDC with a pipeline identity from `src/state-backend` (#11).
- Runbook: prerequisites, deploy, verify, change, retire (with the soft-delete purges), troubleshooting and a cost
  estimate per environment, in `docs/runbook.md` (#12).
- `search_location`: both AI Search services can run in another region than the landing zone; dev uses Norway East,
  because Sweden Central had no AI Search capacity (#9).

### Changed
- Dev carries the tenant policy's exemption tag, so Storage, Key Vault and Cosmos DB keep their public endpoints, and runs
  the Agent Service's standard setup (#7, #9).
- The runbook was followed end to end on a fresh environment; its gaps are fixed and the run is recorded (#12).
- The agent rules and `docs/` describe this Terraform repository and no longer refer to the removed .NET and Python
  files (#6).
- The landing zone's resources are in three groups, one file each: Foundry essentials (`main.foundry.tf`, now with the
  resource group, Log Analytics and Application Insights), the Agent Service dependencies, and the workload
  (`main.workload.tf`). One `deploy_workload` switch replaces `deploy_application_platform` and
  `deploy_application_data`, which now fail the plan when set, and Key Vault moved into the workload. `moved` blocks keep
  existing environments' resources in place (#25).
- The README is a short table of contents; the upstream background moved to root pages: `AGENT-LANDING-ZONE.md`,
  `IMPLEMENTATIONS.md`, `AGENT-SERVICE.md`, `TERRAFORM-PRACTICES.md` and `SOURCES.md` (#29).
- `docs/` holds only what this repository uses: the database and repo-template pages are removed, and the supply-chain
  page covers Terraform and GitHub Actions only (#37).
- Only `README.md` and `LICENSE` stay at the root: the background pages, this changelog and the contributing, conduct,
  security and support pages moved to `docs/`, and every link to them points there (#41).
