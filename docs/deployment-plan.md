# Deployment plan: Agent Landing Zone with Terraform on public endpoints

This plan covers deploying the Agent Landing Zone **infrastructure** with Terraform for a
customer with three requirements. The background (what the landing zone is, the upstream
implementations and their limits) is in [AGENT-LANDING-ZONE.md](AGENT-LANDING-ZONE.md) and
[IMPLEMENTATIONS.md](IMPLEMENTATIONS.md).

| Requirement | What it means here |
|---|---|
| **Public endpoints, no private networking or private DNS** | No VNet, private endpoints, private DNS zones, firewall, jumpbox, Bastion or NAT gateway. Services are reached on their public endpoints and protected by Entra ID authentication, RBAC and, where wanted, IP rules. |
| **No AI Gateway at first** | Applications and agents call the Foundry endpoint directly. Nothing in the design prevents putting the AI Gateway Landing Zone in front later. |
| **Foundry Agent Service dependencies in or out** | One switch per environment deploys or skips the Agent Service's own Cosmos DB, AI Search and Storage (the *standard* agent setup). |

Status: **proposed**. Nothing is built or deployed yet. The decisions in
[Decisions to confirm](#4-decisions-to-confirm) need an answer before phase 2.

## 1. Approach

### The upstream Terraform module can't be used as is

The Agent Landing Zone Terraform pattern module (`Azure/avm-ptn-aiml-landing-zone/azurerm`,
0.5.3) only builds the network-isolated topology:

- it always needs a VNet and subnets,
- it hard-codes `create_private_endpoints = true` for Foundry,
- most of its services default to public access disabled.

The Bicep team's Terraform parity inventory marks every capability as **blocked** for the
public (*standalone-standard*) scenario. Turning flags off doesn't help; the private topology
is structural.

### Options considered

| Option | For | Against | Verdict |
|---|---|---|---|
| **A. Own root module from AVM modules**, centered on the Foundry pattern module `Azure/avm-ptn-aiml-ai-foundry/azurerm` with `create_private_endpoints = false` | Supports public endpoints natively (upstream `public` example). Has switches for the Agent Service and its dependencies. Same AVM modules the landing zone module uses. | We own the composition: naming, RBAC, diagnostics, the workload resources. Not upstream parity, so it needs its own testing. | **Recommended** |
| B. Upstream landing zone module | Least code to write | Can't do public endpoints. Strategy under review upstream. | Rejected |
| C. Fork and patch the landing zone module | Close to upstream | Large, private-first module to maintain against upstream changes; the patch reverses its core design. | Rejected |
| D. Bicep with `azd` (upstream supported path) | Supported by the Agent Landing Zone team, public mode is its default, and it also deploys the Agent Application | Not Terraform, which the customer wants | Keep as the fallback, and as the reference for what to build |

### Scope

**In scope:** the Azure infrastructure of the Agent Landing Zone in *standard* (public)
mode, as Terraform, with remote state, CI checks and a deployment runbook.

**Out of scope for now:**
- **The Agent Application** (UI, orchestrator, hosted agent image, ingestion). Upstream,
  only `azd` hooks configure the services and deploy it; Terraform does not (see
  [decision D1](#4-decisions-to-confirm)).
- **AI Gateway** (API Management): a later phase (see [Later](#later)).
- **Private networking**: the design keeps it possible later, through the Foundry module's
  `create_private_endpoints` and the per-service network settings, but nothing is built for it.

## 2. Target design

### Layout

| Path | Content |
|---|---|
| `src/state-backend/` | One-time bootstrap of the remote state: resource group, storage account and container (Entra ID auth, versioning, soft delete). Its own small local state. |
| `src/landing-zone/` | The root module: providers, variables, outputs, and one file per resource group below: `main.foundry.tf` (group 1), `main.agent-service.tf` (group 2), `main.workload.tf` (group 3). |
| `src/landing-zone/environments/<env>.tfvars` | Per-environment values: region, prefix, switches, models. No secrets. |
| `src/landing-zone/tests/` | `terraform test` files with mocked providers that check what each switch creates. |
| `docs/runbook.md` | Deploy, verify, change and retire steps. |

### Resources, in three groups

The deployed resources fall into three groups. Group 1 is always deployed; groups 2 and 3
each have one switch, so an environment can be "Foundry only", "Foundry and agents", or
the full landing zone.

| Group | What it is for | Resources | Switch | Default |
|---|---|---|---|---|
| **1. Foundry essentials** | Foundry itself and what it needs to run: serve models and host a project | Resource group; Foundry account (public endpoint, local auth disabled); one project; model deployments; Log Analytics workspace and Application Insights (diagnostics, and the project's tracing connection); RBAC for the deployer and user groups on the account and project | none: always | on |
| **2. Agent Service dependencies** | The Foundry Agent Service's own data stores (the *standard* agent setup) | Cosmos DB for NoSQL (at least 3000 RU/s, or serverless), AI Search, Storage account (and the Foundry module's Key Vault); the project connections to them; the account and project capability hosts; the RBAC the Agent Service needs on them | `deploy_agent_service_dependencies` | on |
| **3. Workload** | What applications and agents built on the landing zone run on and use | App Configuration (with the Foundry endpoint and deployment names as settings); Container Registry; Container Apps environment; user-assigned managed identity with its RBAC; Key Vault for workload secrets; a second AI Search and a Storage account for the application's own documents and index | `deploy_workload` | on (see [D2](#4-decisions-to-confirm)) |
| **Not deployed** | | VNet, subnets, NSGs, private endpoints, private DNS, firewall, jumpbox, Bastion, NAT gateway, API Management | none | off |

How the groups relate:

- **Groups 2 and 3 build on group 1, not on each other.** Either can be on or off alone.
  Group 3 reads group 1's outputs (Foundry endpoint, project, deployment names); it never
  uses group 2's resources.
- **Group 3 has its own AI Search and Storage.** Group 2's belong to the Agent Service of
  this Foundry instance only (upstream warns against sharing them), so the application's
  indexes and documents never go there.
- **One resource group and one Terraform state** per environment hold all three groups
  (decided, see [D8](#4-decisions-to-confirm)).

All resources send diagnostics to group 1's Log Analytics workspace, and all take the same
tags.

### The Agent Service dependencies switch

`deploy_agent_service_dependencies` (bool, default `true`) sets the Foundry module's inputs
together, so they can't drift apart:

| Foundry module input | Switch on (*standard* setup) | Switch off |
|---|---|---|
| `create_byor` | `true`: creates Cosmos DB, AI Search, Storage (and the module's Key Vault) | `false` |
| `ai_foundry.create_ai_agent_service` | `true`: account capability host | `false` |
| `ai_projects[*].create_project_connections` | `true`: connections and project capability host | `false` |
| `create_private_endpoints` | `false` | `false` |

An optional `existing_agent_service_dependencies` object (Cosmos DB, AI Search, Storage
resource IDs) reuses a set that already exists, through each definition's
`existing_resource_id`. Upstream warns that such a set must belong to this Foundry
instance only.

With the switch off, the Foundry account, project and model deployments stay. Agents then
use the **basic** setup (Microsoft-managed storage), if they are used at all. Phase 3 checks
that this works as expected.

### Security on public endpoints

Public endpoints are reachable from the internet, so access control replaces network control:

- **Entra ID only:** local (key) authentication off on Foundry, Cosmos DB, AI Search (where
  the clients allow it), Storage (`shared_access_key_enabled = false`, `storage_use_azuread`)
  and App Configuration. Exceptions are listed per service in the PR that adds it.
- **RBAC, least privilege**, assigned by Terraform to managed identities and to Entra groups
  passed as variables, never to individual users in `tfvars`.
- **Optional IP allow lists:** `allowed_ip_ranges` (list, default empty) feeds each service's
  network rules. Empty means open to all networks, with authentication still required.
- **TLS 1.2 minimum**, HTTPS only, soft delete and purge protection on Key Vault.
- **Diagnostics** on every resource, to Log Analytics.

### No AI Gateway, with room for one

Nothing calls the models through API Management. The root module outputs the Foundry
endpoint and the model deployment names, and applications read them from App Configuration.
Adding the AI Gateway Landing Zone later changes the endpoint the applications use, not
this landing zone.

## 3. Phases

Each phase is one issue, one branch and one PR, and each PR is tested before it is opened:
`terraform fmt -check`, `terraform validate`, `terraform test`, and a reviewed
`terraform plan` against the dev subscription. Nothing is applied to Azure without an
explicit go-ahead.

| # | Phase | Delivers | Done when |
|---|---|---|---|
| 0 | **Repository Terraform tooling** | `.gitignore` for state and `.terraform/`, CI job for `fmt`, `validate` and `test`, Dependabot for Terraform, Terraform agent rules, cleanup of the template's .NET and Python references | CI runs the Terraform checks on a sample module |
| 1 | **State backend** | `src/state-backend/`: storage account with Entra ID auth, versioning, soft delete, one container per environment; backend settings documented | Bootstrap applied in dev (after approval); `terraform init` of an empty root module uses it |
| 2 | **Group 1: Foundry essentials** | `src/landing-zone/` with `main.foundry.tf`: resource group, Log Analytics, Application Insights, Foundry account, project and one model deployment, public endpoints, diagnostics, RBAC for the deployer and user groups | Plan reviewed; applied in dev (after approval); the model answers a call made with an Entra ID token |
| 3 | **Group 2: Agent Service dependencies** | `main.agent-service.tf`: `deploy_agent_service_dependencies` and `existing_agent_service_dependencies`, Cosmos DB throughput, connections, capability hosts, RBAC | `terraform test` covers on, off and reuse; dev applied both ways; an agent created in the project stores its thread in our Cosmos DB (on) or works in basic setup (off) |
| 4 | **Group 3: Workload** | `main.workload.tf` behind `deploy_workload`: App Configuration (with the group 1 endpoints and names as settings), Container Registry, Container Apps environment, managed identity, Key Vault, application AI Search and Storage | `terraform test` covers on and off; plan and dev apply reviewed; a test container reads its settings from App Configuration with its managed identity |
| 5 | **Environments and pipeline** | `environments/<env>.tfvars`, GitHub Actions with OIDC: plan on each PR, apply on `main` behind an environment approval | A PR shows the plan; an approved run applies to dev |
| 6 | **Runbook and handover** | `docs/runbook.md`: prerequisites, quotas, deploy, verify, change, retire; cost estimate per environment | Someone else deploys a fresh dev environment from the runbook alone |

Phases 2 to 4 were first built on five groups (core, Foundry, Agent Service dependencies,
application platform, application data); issue #25 regrouped the code into the three groups
above, with `moved` blocks so that no resource is replaced.

Phases 0 and 1 can run in parallel; 2 needs 1; 3 and 4 need 2 and can run in parallel; 5
needs 2; 6 comes last.

### Later

- **AI Gateway:** deploy the AI Gateway Landing Zone (Terraform implementation at
  [aka.ms/ailz/aigateway/terraform](https://aka.ms/ailz/aigateway/terraform)) and point
  applications at it.
- **Private networking:** `create_private_endpoints = true`, a VNet and private DNS. At that
  point, compare again with the upstream landing zone module, which is built for it.
- **Agent Application:** depends on [D1](#4-decisions-to-confirm).

## 4. Decisions to confirm

| # | Decision | Recommendation |
|---|---|---|
| D1 | How is the Agent Application deployed, if at all? Upstream, only `azd` deploys it, and only onto infrastructure it provisioned. | Infrastructure only for now. If the reference application is wanted, plan a separate phase to deploy its components (pinned versions from upstream `manifest.json`) onto the Terraform-built platform, and accept that this is not an upstream-supported combination. |
| D2 | Is the workload group (group 3) needed, and all of it? | Keep it, behind `deploy_workload`, so the landing zone matches upstream *standard* mode. Turn it off for a "Foundry and agents only" environment. Add finer switches inside the group only if an environment needs part of it. |
| D3 | Region(s) and models (names, versions, capacity), per environment | Choose a region with the models, Agent Service and AI Search quota for two services; check quotas before phase 2. |
| D4 | Environments and subscriptions (e.g. dev and prod, one subscription each) | One state and one `tfvars` per environment. |
| D5 | Who deploys, and with which rights? | A pipeline identity with Contributor and Role Based Access Administrator (limited to the roles the landing zone grants) on the target resource group or subscription. Contributor alone can't create the role assignments. |
| D6 | Are IP allow lists wanted on the public endpoints from day one? | Start with them empty in dev; decide per service for prod. |
| D7 | Naming convention | AVM naming with a `name_prefix` and short random suffix, like the upstream modules; or the customer's own convention if there is one. **Since #50:** any `name_prefix` and `environment` are accepted, and each name is made compliant with its type's rules (lowercase, single hyphens, prefix shortened first to fit the length); see [landing-zone.md](landing-zone.md#compliant-names-from-any-prefix-and-environment). |
| D8 | Should the three groups live in separate resource groups, or separate Terraform states? | **Decided (2026-10-27): one resource group and one Terraform state for all three groups.** Why: the Foundry module creates group 2 in the same resource group as the Foundry account, and one state keeps the outputs between groups simple. If the workload must later be owned or retired apart, move group 3 to its own resource group first; group 2 can only move out by creating it outside the module and passing it in through `existing_agent_service_dependencies`. |

## 5. Risks

| Risk | Effect | Mitigation |
|---|---|---|
| Not an upstream-supported combination for the Agent Application | Upstream fixes and runbooks assume Bicep/azd | Keep to infrastructure; follow upstream releases; keep option D as fallback |
| Upstream Terraform strategy is "under review" | Modules or guidance may change | Pin module versions; review upstream changes when bumping them |
| Preview APIs (capability hosts use a `2025-10-01-preview` API version) | Behavior may change | Pin the Foundry module version; test the switch in dev before each bump |
| Cosmos DB throughput too low | Capability host fails to provision | At least 3000 RU/s, or serverless; covered by a `terraform test` check |
| Search quota | Two Search services when groups 2 and 3 are both on | Check quota in the chosen region before phase 3 |
| Soft-deleted Foundry account blocks a redeploy with the same name | Apply fails after a destroy | Random suffix in names; documented purge step in the runbook |
| Public endpoints exposed to the internet | Larger attack surface | Entra ID only, RBAC, optional IP lists, diagnostics, Defender for Cloud recommendations reviewed |
| Module version age gate | The newest version (e.g. Foundry 0.13.0) may be too recent | Use the newest version at least 7 days old (0.12.0 today) |

## 6. Prerequisites

- An Azure subscription per environment, with the resource providers registered:
  `Microsoft.CognitiveServices`, `Microsoft.DocumentDB`, `Microsoft.Search`,
  `Microsoft.Storage`, `Microsoft.KeyVault`, `Microsoft.OperationalInsights`,
  `Microsoft.Insights`, `Microsoft.AppConfiguration`, `Microsoft.ContainerRegistry`,
  `Microsoft.App`.
- Quota for the chosen models, AI Search and Cosmos DB in the chosen region.
- Terraform `>= 1.12` (the Foundry module's minimum), Azure CLI, and the deploying
  identity's rights (see [D5](#4-decisions-to-confirm)).
- An Entra ID group for the people who use the Foundry project.
