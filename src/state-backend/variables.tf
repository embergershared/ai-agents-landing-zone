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
