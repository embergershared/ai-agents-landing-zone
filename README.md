# Azure Agent Landing Zone wrapper

Repo wrapper to deploy Azure AI Agents Landing Zone

> [!NOTE]
> This is a personal project, shared as is to help others. It is not an official Microsoft
> product and is not supported by Microsoft. Review and test it before using any part of it
> in your environment. See [SUPPORT.md](SUPPORT.md).

This repository deploys the **Azure Agent Landing Zone** infrastructure with **Terraform**, on
public endpoints, without an AI Gateway at first. The upstream Terraform landing zone module only
builds network-isolated deployments, so this repository has its own root module, built on the
Foundry AVM pattern module ([why](IMPLEMENTATIONS.md)).

## How this repository deploys it

| Group | What it deploys | Why | Switch |
|---|---|---|---|
| 1. Foundry essentials | Resource group, monitoring, Foundry account, project and models | The minimum to call models and build agents in a Foundry project, with logs and traces for every resource | always on |
| 2. Agent Service dependencies | The Agent Service's own Cosmos DB, AI Search and Storage | The *standard* agent setup: agents' threads, vector stores and files stay in your own resources instead of Microsoft-managed storage | `deploy_agent_service_dependencies` |
| 3. Workload | App Configuration, Container Registry, Container Apps, Key Vault, a second AI Search and Storage | What applications built on the landing zone need to run: their settings, images, hosting, secrets, and their own index and documents, kept apart from the Agent Service's | `deploy_workload` |

It is infrastructure only; the Agent Application is not deployed by Terraform.

## Contents

**Background: the upstream Agent Landing Zone**

| Page | What it covers |
|---|---|
| [AGENT-LANDING-ZONE.md](AGENT-LANDING-ZONE.md) | What the Agent Landing Zone is, key terms, the AI Landing Zones family, what it deploys |
| [IMPLEMENTATIONS.md](IMPLEMENTATIONS.md) | Bicep with azd, the two Terraform modules and their limits, network modes, Bicep settings and their Terraform equivalents |
| [AGENT-SERVICE.md](AGENT-SERVICE.md) | Foundry Agent Service setups and their dependencies |
| [TERRAFORM-PRACTICES.md](TERRAFORM-PRACTICES.md) | Working with Terraform safely: state, sign-in, plan and apply, common failures |
| [SOURCES.md](SOURCES.md) | The upstream sources and the versions read |

**Deploy and operate**

| Page | What it covers |
|---|---|
| [docs/runbook.md](docs/runbook.md) | **Start here:** prerequisites, deploy, verify, change, retire, troubleshooting, cost |
| [docs/deployment-plan.md](docs/deployment-plan.md) | Design, the three groups, phases, decisions and risks |
| [docs/landing-zone.md](docs/landing-zone.md) | The landing zone root module: resources, inputs, settings, checks |
| [docs/state-backend.md](docs/state-backend.md) | The Terraform state backend and its bootstrap |
| [docs/ci-cd.md](docs/ci-cd.md) | CI/CD workflows, repository variables, security settings |

**Contribute**

Every change starts with an issue, gets its own `<type>/<issue>-<slug>` branch, and reaches
`main` only through a PR that closes the issue.

| Page | What it covers |
|---|---|
| [CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | How to contribute |
| [.github/copilot-instructions.md](.github/copilot-instructions.md) | The full rules, for people and AI coding assistants |
| [docs/supply-chain.md](docs/supply-chain.md) | Package feeds, age gate, lock files |
| [docs/database.md](docs/database.md) | Database migrations, backups, rollback |
| [docs/decisions/](docs/decisions/) | Decision records |
| [CHANGELOG.md](CHANGELOG.md) | Changes |
| [SECURITY.md](SECURITY.md) | Reporting a vulnerability |

## License

[MIT](LICENSE)
