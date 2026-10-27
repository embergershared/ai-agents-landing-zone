# The Agent Landing Zone

Facts on this page were read on **2026-10-27** from the sources in [SOURCES.md](SOURCES.md). The
upstream projects move fast; check the versions there before relying on a detail.
Back to the [README](README.md).

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

This repository groups its own resources differently: see [How this repository deploys it](README.md#how-this-repository-deploys-it).
