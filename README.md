# ai-agents-landing-zone

Repo wrapper to deploy Azure AI Agents Landing Zone

> [!NOTE]
> This is a personal project, shared as is to help others. It is not an official Microsoft
> product and is not supported by Microsoft. Review and test it before using any part of it
> in your environment. See [SUPPORT.md](SUPPORT.md).

This repository deploys the **Azure Agent Landing Zone** infrastructure with **Terraform**.
This page keeps what we learned about the upstream projects in one place: what the Agent
Landing Zone is, which implementations exist, what each one can and cannot do, and how they
map to this repository. The deployment itself is planned in
[docs/deployment-plan.md](docs/deployment-plan.md).

> [!IMPORTANT]
> **The upstream Terraform module does not support public endpoints.** The Agent Landing
> Zone Terraform pattern module always creates a virtual network, subnets and private
> endpoints. A deployment on public endpoints (what Bicep calls *standard* mode) needs our
> own Terraform root module, built on the Foundry AVM pattern module, which does support
> them. See [Implementations](#implementations) and the [plan](docs/deployment-plan.md).

Facts below were read on **2026-10-27** from the sources listed in [Sources](#sources).
The upstream projects move fast; check the versions there before relying on a detail.

## Contents

- [What the Agent Landing Zone is](#what-the-agent-landing-zone-is)
- [The AI Landing Zones family](#the-ai-landing-zones-family)
- [Implementations](#implementations)
- [Network modes: standard or network-isolated](#network-modes-standard-or-network-isolated)
- [Foundry Agent Service and its dependencies](#foundry-agent-service-and-its-dependencies)
- [What the landing zone deploys](#what-the-landing-zone-deploys)
- [Bicep settings and their Terraform equivalents](#bicep-settings-and-their-terraform-equivalents)
- [Working with Terraform safely](#working-with-terraform-safely)
- [How this repository deploys it](#how-this-repository-deploys-it)
- [Sources](#sources)
- [Getting started](#getting-started)
- [How work is done here](#how-work-is-done-here)

## What the Agent Landing Zone is

The Agent Landing Zone is Microsoft's reference **workload landing zone** for AI agents on
Azure: a ready-made, secure foundation on which agents built with **Microsoft Foundry** run.
It replaces the former *GPT-RAG* project (same project, broader scope).

It has two separate parts:

| Part | What it is |
|---|---|
| **Infrastructure** | The Azure resources: Microsoft Foundry account, project and model deployments, the Foundry Agent Service and its data stores, AI Search, Storage, Key Vault, App Configuration, Container Registry, Container Apps, monitoring, identities and RBAC, and, when chosen, private networking. |
| **Agent Application** | A reference application that runs on that infrastructure: a web chat UI, an orchestrator (the code that coordinates model calls, retrieval and tools for each turn) and an optional ingestion service. By default, the orchestrator runs as a **hosted agent** in Foundry Agent Service, using the `maf_lite` strategy and native Foundry IQ Blob ingestion. |

Some terms used on this page:

| Term | Meaning |
|---|---|
| **Microsoft Foundry** | Azure's platform for models and agents. A Foundry **account** (`Microsoft.CognitiveServices/accounts`) holds model deployments; **projects** inside it isolate agents and their data. |
| **Foundry Agent Service** | The Foundry service that hosts and runs agents. Turned on through a **capability host** on the account and project. |
| **Hosted agent** | An agent whose code runs as a container image inside Foundry Agent Service. |
| **Foundry IQ** | Foundry's knowledge layer: knowledge sources and knowledge bases backed by Azure AI Search. |
| **AI Gateway** | An Azure API Management layer in front of models, for central routing, authentication and token policies. |
| **AVM** | [Azure Verified Modules](https://aka.ms/AVM): Microsoft-maintained Bicep and Terraform modules. *Pattern* modules (`ptn`) combine *resource* modules (`res`). |

Two runbooks exist upstream: **Deploy infra only** (the Azure resources, no application
code) and **Deploy full stack** (infrastructure plus the Agent Application). Both use Bicep
with the Azure Developer CLI (`azd`).

## The AI Landing Zones family

The [AI Landing Zones](https://azure.github.io/AI-Landing-Zones/) site groups three related
pieces. They can be used alone or together.

| Piece | Purpose | Bicep | Terraform |
|---|---|---|---|
| **Agent Landing Zone** | Workload foundation for AI apps and agents, with the default Agent Application. | [Azure/agent-landing-zone](https://github.com/Azure/agent-landing-zone) (infra from [bicep-ptn-aiml-landing-zone](https://github.com/Azure/bicep-ptn-aiml-landing-zone)) | [avm-ptn-aiml-landing-zone](https://github.com/Azure/terraform-azurerm-avm-ptn-aiml-landing-zone) |
| **AI Gateway Landing Zone** | Shared API Management gateway that governs access to Foundry models for many workloads. Deployed separately; the Agent Landing Zone does not create or connect it. | [aka.ms/ailz/apim](https://aka.ms/ailz/apim) | [aka.ms/ailz/aigateway/terraform](https://aka.ms/ailz/aigateway/terraform) |
| **Foundry AVM modules** | Building block for a Foundry account, projects, model deployments and Agent Service dependencies. | [avm/ptn/ai-ml/ai-foundry](https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/ai-ml/ai-foundry) | [avm-ptn-aiml-ai-foundry](https://registry.terraform.io/modules/Azure/avm-ptn-aiml-ai-foundry/azurerm/latest) |

The reference architectures come in two shapes:

- **Standalone:** the workload owns its network, DNS and operations, with no platform hub.
- **With Platform Hub:** the workload connects (peering, routes, DNS) to a hub owned by a
  platform team, which supplies shared connectivity, firewall, DNS or monitoring.

The architecture diagrams on the site show private-network deployments. Public-endpoint
deployments use the same services without the network layer.

## Implementations

### Bicep with azd: the supported Agent Landing Zone path

[Azure/agent-landing-zone](https://github.com/Azure/agent-landing-zone) is the main project.
Release **v4.4.0** pins its pieces in `manifest.json`:

| Piece | Repository | Pinned version |
|---|---|---|
| Infrastructure (Bicep, copied into `infra/`) | [Azure/bicep-ptn-aiml-landing-zone](https://github.com/Azure/bicep-ptn-aiml-landing-zone) | v2.7.3 |
| Agent App UI | [Azure/agent-app-ui](https://github.com/Azure/agent-app-ui) | v3.3.0 |
| Agent App Orchestrator | [Azure/agent-app-orchestrator](https://github.com/Azure/agent-app-orchestrator) | v5.2.1 |
| Agent App Ingestion (optional) | [Azure/agent-app-ingestion](https://github.com/Azure/agent-app-ingestion) | v3.1.1 |

`azd` runs the whole lifecycle through hooks: it composes parameters and runs preflight
checks (`preprovision`), configures the services and publishes runtime settings to App
Configuration under the `agent-lz` label (`postprovision`), builds the hosted agent image,
and deploys the application (`predeploy`, `azd deploy`). Settings come from `azd` environment
variables (such as `NETWORK_ISOLATION`) and from the root `main.parameters.json`.

This is the only path that deploys and configures the **Agent Application**.

### Terraform: the AI/ML landing zone pattern module

[Azure/terraform-azurerm-avm-ptn-aiml-landing-zone](https://github.com/Azure/terraform-azurerm-avm-ptn-aiml-landing-zone)
(registry `Azure/avm-ptn-aiml-landing-zone/azurerm`, latest **0.5.3**, published
2026-09-25) builds the landing zone infrastructure. Its upstream status matters:

- **Its strategy is under review.** The docs say so, and point Agent Landing Zone users to
  the Bicep/azd runbooks.
- **It is infrastructure only.** `terraform apply` does not configure services, prepare the
  hosted agent image or deploy the Agent Application.
- **It only does network-isolated deployments.** It always needs a VNet (new or existing),
  always creates private endpoints for Foundry (`create_private_endpoints = true` is
  hard-coded) and defaults most services to public access disabled. The Bicep team's
  [Terraform parity inventory](https://github.com/Azure/agent-landing-zone/blob/main/infra/docs/terraform-parity.md)
  marks **every** capability as *blocked* for the public (*standalone-standard*) scenario.
- **It deploys an AI Gateway by default:** `apim_definition.deploy` defaults to `true`.

It ships four examples, which are test configurations to harden before production use:

| Example | Use |
|---|---|
| `standalone` | Network-isolated foundation without a platform landing zone. |
| `default` | Integration with a platform hub (creates a demo hub). |
| `standalone-byo-vnet` | Standalone on an existing VNet. |
| `default-byo-vnet` | Platform integration on an existing VNet. |

Main inputs: `location`, `resource_group_name`, `name_prefix`, `flag_platform_landing_zone`
(default `true`), `vnet_definition`, `ai_foundry_definition`, one `*_definition` object per
service (each with a `deploy` switch), `private_dns_zones` and `use_internet_routing`.
Providers: `azurerm ~> 4.0`, `azapi ~> 2.12`; Terraform `>= 1.9, < 2.0`.

### Terraform: the Foundry pattern module

[Azure/terraform-azurerm-avm-ptn-aiml-ai-foundry](https://github.com/Azure/terraform-azurerm-avm-ptn-aiml-ai-foundry)
(registry `Azure/avm-ptn-aiml-ai-foundry/azurerm`) is the module the landing zone module
uses for Foundry. Used directly, it supports **public endpoints**, and it has a ready-made
`public` example:

| Input | Default | Effect |
|---|---|---|
| `create_private_endpoints` | `false` | Private endpoints for Foundry, Cosmos DB, Key Vault and AI Search. Off means public endpoints, and no VNet or private DNS needed. |
| `create_byor` | `false` | Create the Agent Service dependencies (AI Search, Cosmos DB, Storage, Key Vault). Each one can also point to an existing resource with `existing_resource_id`. |
| `ai_foundry.create_ai_agent_service` | `false` | Create the account-level Agent Service capability host. |
| `ai_projects[*].create_project_connections` | `false` | Connect the project to Cosmos DB, AI Search and Storage. With the Agent Service on, this also creates the project capability host (the *standard* agent setup). |
| `ai_foundry.public_network_access_enabled` | derived | Follows `create_private_endpoints` when not set. |
| `ai_foundry.network_acls` | allow all | Restrict the public endpoint, e.g. to IP ranges. |
| `ai_model_deployments` | none | Model deployments (format, name, version, SKU and capacity). |

Examples: `basic`, `public`, `public-byor` (existing dependencies), `public-cmk`,
`private`, `private-byor`, plus CMK and user-assigned identity variants. Requires Terraform
`>= 1.12`, `azurerm ~> 4.38`, `azapi ~> 2.12`. Versions: **0.12.0** (2026-10-15) and
**0.13.0** (2026-10-25). This repository's 7-day age gate allows 0.12.0 today.

### Azure portal

A *Deploy to Azure* button on the AI Landing Zones site deploys the infrastructure
through ARM. It does not run the `azd` hooks or the hosted agent workflow.

## Network modes: standard or network-isolated

Bicep chooses with one setting, `NETWORK_ISOLATION` (default `false`).

| Area | Standard (`NETWORK_ISOLATION=false`) | Network-isolated (`true`) |
|---|---|---|
| Access to services | Public endpoints, protected by authentication and authorization | Private endpoints; public access disabled unless `allowedIpRanges` is set |
| DNS | Public DNS | Private DNS zones linked to the VNet |
| VNet, firewall, jumpbox, Bastion, NAT gateway | Not deployed | Deployed by default |
| Container image builds | Local Docker or regular ACR Tasks | ACR Task agent pool inside the VNet |
| Where deployment commands run | Any authorized machine that reaches the endpoints | A machine connected to the VNet |
| Terraform landing zone module | **Not supported** | Supported (`flag_platform_landing_zone = false` for standalone) |
| Terraform Foundry module | Supported (`create_private_endpoints = false`) | Supported |

Azure Resource Manager stays public in both modes. A public endpoint is still protected by
Microsoft Entra ID authentication and RBAC, and most services accept IP rules to narrow it.

## Foundry Agent Service and its dependencies

[Microsoft Learn](https://learn.microsoft.com/azure/foundry/agents/environment-setup) describes
three setups:

| Setup | Where agent data lives | Customer-managed keys | Private networking |
|---|---|---|---|
| **Basic** | Microsoft-managed storage, logically separated | No | No |
| **Standard, public networking** | Your own Azure resources | Yes | No |
| **Standard, private networking** | Your own Azure resources, in your VNet | Yes | Yes |

The standard setup's dependencies (the *bring-your-own resources*):

| Resource | Holds |
|---|---|
| Azure Storage | Files uploaded by developers and users |
| Azure AI Search | Vector stores created by agents |
| Azure Cosmos DB for NoSQL | Threads, messages, conversation history, agent definitions |

Facts to plan around:

- **Cosmos DB throughput:** at least **3000 RU/s** for the account (serverless works too).
  Each project gets several containers of 1000 RU/s each (3 for the classic runtime, 2 more
  for the new one). Too little throughput makes the capability host fail to provision.
- **They are a second set.** These dependencies belong to the Foundry instance only. They are
  separate from the AI Search and Storage the application uses for its own data, so a full
  deployment has **two** Search services and **two** Storage accounts. Search quota must
  cover both.
- **Permissions:** creating a standard setup needs role-assignment rights
  (`Microsoft.Authorization/roleAssignments/write`, e.g. *Role Based Access Administrator*),
  besides the rights to create the resources. Contributor alone is not enough.
- **Bicep switch:** `DEPLOY_AAF_AGENT_SVC` (default `true`). Off, the Foundry account stays
  but the second Search, Storage and Cosmos DB are not created. Upstream notes the default
  hosted-agent path needs it on. Existing dependencies can be reused with
  `aiSearchResourceId`, `aiFoundryStorageAccountResourceId` and
  `aiFoundryCosmosDBAccountResourceId`, but only a set dedicated to this Foundry instance.

## What the landing zone deploys

The Bicep implementation deploys these layers. Most resources have a switch, and many can
reuse an existing resource.

| Layer | Resources | Default |
|---|---|---|
| Foundry and models | Foundry account, project, model deployments | On |
| Agent Service dependencies | Foundry-owned AI Search, Storage, Cosmos DB, plus the capability hosts | On (`DEPLOY_AAF_AGENT_SVC`) |
| Application data | AI Search, Storage, Key Vault (plus a Cosmos DB in some application topologies) | On, each switchable |
| Application platform | App Configuration, Container Registry, Container Apps environment and apps, managed identities and RBAC | On, each switchable |
| Monitoring | Log Analytics, Application Insights | On, or reuse existing |
| Private networking | VNet, subnets, NSGs, private endpoints, private DNS, Azure Firewall, jumpbox, Bastion, NAT gateway | Only with `NETWORK_ISOLATION=true` |
| Add-ons | Application Gateway WAF (public ingress for the UI), Speech, Bing grounding, ACR build pool | Off |

The default application topology, `hosted-no-panel`, runs the orchestrator as a hosted
agent, has no admin panel, and has no application Cosmos DB. That doesn't remove the Agent
Service's own Cosmos DB.

## Bicep settings and their Terraform equivalents

The settings that matter for this repository's first deployment:

| Need | Bicep / azd | Terraform landing zone module | Terraform Foundry module |
|---|---|---|---|
| Public endpoints, no private DNS | `NETWORK_ISOLATION=false` | Not possible | `create_private_endpoints = false` |
| No AI Gateway | Nothing to do: Agent Bicep doesn't deploy one | `apim_definition = { deploy = false }` | Nothing to do: not in the module |
| Agent Service dependencies on or off | `DEPLOY_AAF_AGENT_SVC=true/false` | `ai_foundry_definition.create_byor` (default `true`) and `ai_foundry.create_ai_agent_service` (default `false`), always behind private endpoints | `create_byor`, `ai_foundry.create_ai_agent_service`, `create_project_connections` |
| Reuse existing dependencies | `aiSearchResourceId`, `aiFoundryStorageAccountResourceId`, `aiFoundryCosmosDBAccountResourceId` | `existing_resource_id` per definition | `existing_resource_id` per definition |
| Restrict public access by IP | `allowedIpRanges` | Per service | `network_acls`, `ip_range_filter`, `network_rule_set` per service |

## Working with Terraform safely

From the upstream Terraform guide, and this repository's own rules:

- **State is sensitive.** State and plan files can hold secrets: never commit them. Keep
  state in an Azure Storage backend with Entra ID authentication, locking, versioning and
  one state per environment, set up before the first `terraform init`.
- **Sign-in:** `az login` and `az account set` on a workstation; OIDC (workload identity
  federation) in pipelines. No client secrets in `.tf` files, shell history or variables.
- **Plan, review, apply:** `terraform init`, `terraform validate`,
  `terraform plan -out=<file>`, `terraform show <file>`, then `terraform apply <file>` after
  review. Review additions, replacements, deletions, role assignments, public access and
  recurring costs. A saved plan applies without prompting, so get approval first.
- **Lock file:** commit `.terraform.lock.hcl`; don't run `terraform init -upgrade` as a
  generic fix.
- **Verify after apply:** list the resources, check the Foundry project and model
  deployments, check diagnostics, and check data-plane access with the intended identity,
  not just that the resources exist.
- **Common failures:** missing role-assignment rights (`AuthorizationFailed`), resource
  provider not registered, model or quota not available in the region, a resource that
  already exists in another state, and a Foundry account name still held by soft delete.
- **Changes and retirement:** renaming or moving regions can replace resources and lose data.
  Retire with `terraform plan -destroy -out=<file>`, review it, and apply only after
  approval. Don't delete things to work around a failed apply.

## How this repository deploys it

Our target is a deployment that:

- uses **public endpoints only**: no private networking and no private DNS;
- has **no AI Gateway** at first, with room to add the AI Gateway Landing Zone later;
- lets each environment **deploy or skip the Foundry Agent Service dependencies**.

The upstream landing zone module can't do the first point, so this repository builds its own
Terraform root module from AVM modules, centered on the Foundry pattern module with
`create_private_endpoints = false`. It is infrastructure only; the Agent Application is
not deployed by Terraform. The phases, decisions and risks are in
[docs/deployment-plan.md](docs/deployment-plan.md).

## Sources

Read on 2026-10-27.

| Source | Version read |
|---|---|
| [AI Landing Zones documentation](https://azure.github.io/AI-Landing-Zones/) ([source](https://github.com/Azure/AI-Landing-Zones)) | `main` at `1222404` |
| [Agent Landing Zone: Terraform templates](https://azure.github.io/AI-Landing-Zones/agent-landing-zone/terraform/) | same |
| [Terraform infrastructure reference](https://azure.github.io/AI-Landing-Zones/terraform/) | same |
| [Agent Landing Zone deployment choices](https://azure.github.io/AI-Landing-Zones/agent-landing-zone/planning/), [network isolation](https://azure.github.io/AI-Landing-Zones/agent-landing-zone/network-isolation/), [deployment settings](https://azure.github.io/AI-Landing-Zones/agent-landing-zone/configuration/) | same |
| [Azure/agent-landing-zone](https://github.com/Azure/agent-landing-zone) (Bicep/azd) | v4.4.0, `main` at `260197b` |
| [Terraform parity inventory](https://github.com/Azure/agent-landing-zone/blob/main/infra/docs/terraform-parity.md) | assessed 2026-08-21, Terraform module v0.5.1 |
| [terraform-azurerm-avm-ptn-aiml-landing-zone](https://github.com/Azure/terraform-azurerm-avm-ptn-aiml-landing-zone) | 0.5.3, `main` at `13f63c3` (still hard-codes `create_private_endpoints = true`) |
| [terraform-azurerm-avm-ptn-aiml-ai-foundry](https://github.com/Azure/terraform-azurerm-avm-ptn-aiml-ai-foundry) | v0.12.0 (examples and switches checked at that tag) |
| [Microsoft Learn: set up your agent environment](https://learn.microsoft.com/azure/foundry/agents/environment-setup) | 2026-10-27 |
| [Microsoft Learn: standard agent setup](https://learn.microsoft.com/azure/foundry/agents/concepts/standard-agent-setup) and [use your own resources](https://learn.microsoft.com/azure/foundry/agents/how-to/use-your-own-resources) | 2026-10-27 |

## Getting started

There is no Terraform code yet. It arrives in the phases of the
[deployment plan](docs/deployment-plan.md), with the build and deploy commands.

## How work is done here

Every change starts with an issue, gets its own `<type>/<issue>-<slug>` branch, and reaches
`main` only through a PR that closes the issue. The full rules, for people and AI coding
assistants alike, are in [.github/copilot-instructions.md](.github/copilot-instructions.md);
[CONTRIBUTING.md](CONTRIBUTING.md) has the short version.

| Topic | Where |
|---|---|
| Deployment plan | [docs/deployment-plan.md](docs/deployment-plan.md) |
| Contributing | [CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) |
| Reporting a vulnerability | [SECURITY.md](SECURITY.md) |
| CI/CD workflows, ruleset, security settings, repository variables | [docs/ci-cd.md](docs/ci-cd.md) |
| Package feeds, age gate, lock files | [docs/supply-chain.md](docs/supply-chain.md) |
| Database migrations, backups, rollback | [docs/database.md](docs/database.md) |
| Decisions | [docs/decisions/](docs/decisions/) |
| Changes | [CHANGELOG.md](CHANGELOG.md) |

## License

[MIT](LICENSE)
