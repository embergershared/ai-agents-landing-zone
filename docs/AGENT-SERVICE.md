# Foundry Agent Service and its dependencies

Facts on this page were read on **2026-10-27** from the sources in [SOURCES.md](SOURCES.md). The
upstream projects move fast; check the versions there before relying on a detail.
Back to the [README](../README.md).

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
