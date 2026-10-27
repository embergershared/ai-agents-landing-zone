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

### Changed
- The agent rules and `docs/` describe this Terraform repository and no longer refer to the removed .NET and Python
  files (#6).
