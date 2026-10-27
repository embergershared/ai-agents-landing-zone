# 0001: Standard agent setup: no Key Vault, Foundry User on the account

- **Date:** 2026-10-27
- **Status:** accepted
- **Issue:** #44

## Context

Microsoft's [standard agent setup](https://learn.microsoft.com/azure/foundry/agents/concepts/standard-agent-setup)
lists the resources and roles the Agent Service needs. Checked against it, the landing zone
with `deploy_agent_service_dependencies = true` missed four items. Two are now deployed (#44):
the project's Application Insights connection for traces, and Storage Account Contributor for
the project on the Agent Service storage account. The two below were decided instead.

**Key Vault.** The article lists a Key Vault "for managing secrets and connection strings".
Foundry uses a customer Key Vault only through an account connection of category
`AzureKeyVault` ([Set up a Key Vault connection](https://learn.microsoft.com/azure/foundry/how-to/set-up-key-vault-connection)):

- It must be the account's first connection: Foundry refuses it while any other connection
  exists, and doesn't migrate secrets.
- The AVM Foundry module creates the project's connections itself. A Key Vault connection made
  next to it needs the module's account ID, so the module can't wait for it (a cycle).
- Dev already has connections. Adding it there means deleting every connection, which the
  capability host keeps locked, so in practice recreating the project.
- Every connection here uses Entra ID (`AAD` or the project's managed identity), so Foundry has
  no secrets to store.

**Foundry User scope.** The article gives developers Foundry User on the **project**. The
landing zone gives it to `project_user_principals` on the **account**, which includes the
project. The runbook's check calls a model on the account's OpenAI endpoint
(`docs/landing-zone.md`), which needs the role on the account.

## Options

| Option | For | Against |
|---|---|---|
| Key Vault: none | Nothing unused to run or secure; no secrets exist | Doesn't match the article's resource list |
| Key Vault: created, not connected | Matches the list | An empty vault Foundry never uses |
| Key Vault: created and connected | Foundry stores connection secrets in our vault | Module workaround needed; recreate the project in dev; still no secrets to store |
| Foundry User on the account | Account endpoints and the project both work | Wider than the article asks |
| Foundry User on the project | Least privilege, as in the article | Calls to the account's OpenAI endpoint fail; developers move to the project endpoint |

## Decision

No Key Vault for the Agent Service. Foundry User stays on the account for `project_user_principals`.

## Consequences

- A connection that needs a secret (an API key) is stored in Foundry's Microsoft-managed Key
  Vault. Revisit this decision before adding one, and before the first deployment of a new
  environment, where a Key Vault connection costs nothing to add first.
- `project_user_principals` can use every project on the account. Keep it to the groups that
  may; give a project-only group its role on that project by hand or in a later change.
- The workload's Key Vault (`deploy_workload`) is for the applications' secrets and is not
  connected to Foundry.
