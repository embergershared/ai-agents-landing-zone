# Azure Agent Landing Zone wrapper

Repo wrapper to deploy Azure AI Agents Landing Zone

> [!NOTE]
> This is a personal project, shared as is to help others. It is not an official Microsoft
> product and is not supported by Microsoft. Review and test it before using any part of it
> in your environment. See [SUPPORT.md](docs/SUPPORT.md).

This repository deploys the **Azure Agent Landing Zone** infrastructure with **Terraform**, on
public endpoints, without an AI Gateway at first. The upstream Terraform landing zone module only
builds network-isolated deployments, so this repository has its own root module, built on the
Foundry AVM pattern module ([why](docs/IMPLEMENTATIONS.md)).

## How this repository deploys it

| Group | What it deploys | Why | Switch |
|---|---|---|---|
| 1. Foundry essentials | Resource group, monitoring, Foundry account, project and models | The minimum to call models and build agents in a Foundry project, with logs and traces for every resource | always on |
| 2. Agent Service dependencies | The Agent Service's own Cosmos DB, AI Search and Storage | The *standard* agent setup: agents' threads, vector stores and files stay in your own resources instead of Microsoft-managed storage | `deploy_agent_service_dependencies` |
| 3. Workload | App Configuration, Container Registry, Container Apps, Key Vault, a second AI Search and Storage | What applications built on the landing zone need to run: their settings, images, hosting, secrets, and their own index and documents, kept apart from the Agent Service's | `deploy_workload` |

It is infrastructure only; the Agent Application is not deployed by Terraform.


## Quick deploy steps

```pwsh
# Login and set variables
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
$env:ARM_SUBSCRIPTION_ID = az account show --query id -o tsv

# Terraform init + configure backend to an existing Azure Storage Account container
Set-Location src/landing-zone
$envName = 'fullrun'
# Check the values before initializing terraform
code "environments/$envName.backend.hcl"
terraform init -reconfigure -backend-config="environments/$envName.backend.hcl"

# Prepare for required permissions for users
# Gives each listed group or user "Foundry User" on the Foundry account and "Log Analytics Reader" on Application Insights (to read traces)
# $env:TF_VAR_project_user_principals = '{"users":{"principal_id":"<entra-group-object-id>","principal_type":"Group"}}'
$GroupDisplayName = "proj-swec-s3-ailz-agent-svc-fullrun-entra-group"
$env:TF_VAR_project_user_principals = @{ users = @{ principal_id = (az ad group show --group $GroupDisplayName --query id -o tsv); principal_type = 'Group' } } | ConvertTo-Json -Compress

# Gives you "App Configuration Data Owner", so Terraform can write the landingzone: settings into App Configuration with your Entra identity
# $env:TF_VAR_app_settings_writer_principals = '{"me":{"principal_id":"<your-entra-object-id>","principal_type":"User"}}'
$env:TF_VAR_app_settings_writer_principals = @{ me = @{ principal_id = (az ad signed-in-user show --query id -o tsv); principal_type = 'User' } } | ConvertTo-Json -Compress

# Check the content of the values terraform will use
code "environments/$envName.tfvars"

# Deploy Group 1: Foundry resource, project and model
terraform plan -compact-warnings -var-file="environments/$envName.tfvars" -var="deploy_agent_service_dependencies=false" -var="deploy_workload=false" -out "$envName-g1.tfplan"
terraform apply "$envName-g1.tfplan"; Remove-Item "$envName-g1.tfplan"

# Deploy Group 2: Foundry Standard (allows persistence of prompts, uploaded files and Foundry IQ)
terraform plan -compact-warnings -var-file="environments/$envName.tfvars" -var="deploy_workload=false" -out "$envName-g2.tfplan"
terraform apply "$envName-g2.tfplan"; Remove-Item "$envName-g2.tfplan"

# Deploy Group 3: Application platform based on Container Apps to run coded agents
terraform plan -compact-warnings -var-file="environments/$envName.tfvars" -out "$envName-g3.tfplan"
terraform apply "$envName-g3.tfplan"; Remove-Item "$envName-g3.tfplan"
```

> Note: the sample agent is not deployed with terraform

- To delete all resources:
```pwsh
terraform destroy -var-file="environments/$envName.tfvars"
```

## Contents

**Background: the upstream Agent Landing Zone**

| Page | What it covers |
|---|---|
| [AGENT-LANDING-ZONE.md](docs/AGENT-LANDING-ZONE.md) | What the Agent Landing Zone is, key terms, the AI Landing Zones family, what it deploys |
| [IMPLEMENTATIONS.md](docs/IMPLEMENTATIONS.md) | Bicep with azd, the two Terraform modules and their limits, network modes, Bicep settings and their Terraform equivalents |
| [AGENT-SERVICE.md](docs/AGENT-SERVICE.md) | Foundry Agent Service setups and their dependencies |
| [TERRAFORM-PRACTICES.md](docs/TERRAFORM-PRACTICES.md) | Working with Terraform safely: state, sign-in, plan and apply, common failures |
| [SOURCES.md](docs/SOURCES.md) | The upstream sources and the versions read |

**Deploy and operate**

| Page | What it covers |
|---|---|
| [docs/runbook.md](docs/runbook.md) | **Start here:** prerequisites, deploy, verify, change, retire, troubleshooting, cost |
| [docs/deployment-plan.md](docs/deployment-plan.md) | Design, the three groups, phases, decisions and risks |
| [docs/landing-zone.md](docs/landing-zone.md) | The landing zone root module: resources, inputs, settings, checks |
| [docs/state-backend.md](docs/state-backend.md) | The Terraform state backend and its bootstrap |
| [docs/ci-cd.md](docs/ci-cd.md) | CI/CD workflows, repository variables and secrets, security settings |

**Contribute**

Every change starts with an issue, gets its own `<type>/<issue>-<slug>` branch, and reaches
`main` only through a PR that closes the issue.

| Page | What it covers |
|---|---|
| [CONTRIBUTING.md](docs/CONTRIBUTING.md), [CODE_OF_CONDUCT.md](docs/CODE_OF_CONDUCT.md) | How to contribute |
| [.github/copilot-instructions.md](.github/copilot-instructions.md) | The full rules, for people and AI coding assistants |
| [docs/supply-chain.md](docs/supply-chain.md) | Package feeds, age gate, lock files |
| [docs/decisions/](docs/decisions/) | Decision records |
| [CHANGELOG.md](docs/CHANGELOG.md) | Changes |
| [SECURITY.md](docs/SECURITY.md) | Reporting a vulnerability |

## License

[MIT](LICENSE)
