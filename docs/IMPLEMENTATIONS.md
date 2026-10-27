# Agent Landing Zone implementations

Facts on this page were read on **2026-10-27** from the sources in [SOURCES.md](SOURCES.md). The
upstream projects move fast; check the versions there before relying on a detail.
Back to the [README](../README.md).

The ways to deploy the Agent Landing Zone, what each one can and cannot do, and how their settings map
to each other.

## Bicep with azd: the supported Agent Landing Zone path

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

## Terraform: the AI/ML landing zone pattern module

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

## Terraform: the Foundry pattern module

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

## Azure portal

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

## Bicep settings and their Terraform equivalents

The settings that matter for this repository's first deployment:

| Need | Bicep / azd | Terraform landing zone module | Terraform Foundry module |
|---|---|---|---|
| Public endpoints, no private DNS | `NETWORK_ISOLATION=false` | Not possible | `create_private_endpoints = false` |
| No AI Gateway | Nothing to do: Agent Bicep doesn't deploy one | `apim_definition = { deploy = false }` | Nothing to do: not in the module |
| Agent Service dependencies on or off | `DEPLOY_AAF_AGENT_SVC=true/false` | `ai_foundry_definition.create_byor` (default `true`) and `ai_foundry.create_ai_agent_service` (default `false`), always behind private endpoints | `create_byor`, `ai_foundry.create_ai_agent_service`, `create_project_connections` |
| Reuse existing dependencies | `aiSearchResourceId`, `aiFoundryStorageAccountResourceId`, `aiFoundryCosmosDBAccountResourceId` | `existing_resource_id` per definition | `existing_resource_id` per definition |
| Restrict public access by IP | `allowedIpRanges` | Per service | `network_acls`, `ip_range_filter`, `network_rule_set` per service |
