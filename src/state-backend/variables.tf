variable "location" {
  type        = string
  description = "Azure region of the state backend."
  default     = "swedencentral"
}

variable "name_prefix" {
  type        = string
  description = "Short prefix of every resource name (lowercase letters and digits)."
  default     = "alz"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.name_prefix))
    error_message = "name_prefix is 2 to 8 lowercase letters or digits, starting with a letter."
  }
}

variable "environments" {
  type        = set(string)
  description = "Environments that get a state container (tfstate-<env>)."
  default     = ["dev"]

  validation {
    condition     = length(var.environments) > 0 && alltrue([for e in var.environments : can(regex("^[a-z][a-z0-9-]{1,19}$", e))])
    error_message = "environments holds at least one name of 2 to 20 lowercase letters, digits or hyphens."
  }
}

variable "replication_type" {
  type        = string
  description = "Storage account replication. ZRS keeps the state through a zone outage."
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type is one of LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS."
  }
}

variable "soft_delete_retention_days" {
  type        = number
  description = "Days a deleted state blob or container can be restored."
  default     = 30

  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "soft_delete_retention_days is between 1 and 365."
  }
}

variable "state_contributor_principal_ids" {
  type        = set(string)
  description = "Object IDs of the users, groups or managed identities that read and write state (Storage Blob Data Contributor on the account)."
  default     = []
}

variable "grant_current_principal" {
  type        = bool
  description = "Also give the identity running this bootstrap read and write access to the state."
  default     = true
}

variable "allowed_ip_ranges" {
  type        = list(string)
  description = "Public IP ranges (CIDR) allowed to reach the storage account. Empty: all networks, Entra ID still required."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Tags on every resource."
  default     = {}
}

variable "github_deployer" {
  type = object({
    repository     = string
    environments   = map(string)
    subject_prefix = optional(string)
  })
  description = "Pipeline identity for GitHub Actions: repository (owner/name); per GitHub environment, the resource ID of the scope it deploys to (a resource group or subscription); and the OIDC subject prefix GitHub sends, when it isn't repo:<owner>/<name> (immutable subjects: repo:<owner>@<owner-id>/<name>@<repo-id>). Null: no pipeline identity."
  default     = null

  validation {
    condition     = var.github_deployer == null || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_deployer.repository))
    error_message = "github_deployer.repository is owner/name."
  }

  validation {
    condition     = var.github_deployer == null || try(var.github_deployer.subject_prefix == null || startswith(var.github_deployer.subject_prefix, "repo:"), false)
    error_message = "github_deployer.subject_prefix starts with repo: (read it with: gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix)."
  }
}

variable "deployer_assignable_role_ids" {
  type        = list(string)
  description = "Role definition IDs (GUIDs) the pipeline identity may assign and remove: the roles the landing zone grants. Add one here when the landing zone starts granting it."
  default = [
    "53ca6127-db72-4b80-b1b0-d745d6d5456d", # Foundry User
    "5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b", # App Configuration Data Owner
    "516239f1-63e1-4d78-a4de-a74fb236a071", # App Configuration Data Reader
    "7f951dda-4ed3-4680-a7ca-43fe172d538d", # AcrPull
    "8ebe5a00-799e-43f5-93ac-243d3dce84a7", # Search Index Data Contributor
    "7ca78c08-252a-4471-8644-bb5ff32d4ba0", # Search Service Contributor
    "ba92f5b4-2d11-453d-a403-e96b0029c9fe", # Storage Blob Data Contributor
    "b7e6dc6d-f1e8-4753-8033-0f276bb0955b", # Storage Blob Data Owner
    "230815da-be43-4aae-9cb4-875f7bd000aa", # Cosmos DB Operator
    "17d1049b-9a84-46fb-8f53-869881c3d3ab", # Storage Account Contributor
    "3913510d-42f4-4e42-8a64-420c390055eb", # Monitoring Metrics Publisher
    "73c42c96-874c-492b-b04d-ab87d138a893", # Log Analytics Reader
  ]
}
