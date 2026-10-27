variable "location" {
  type        = string
  description = "Azure region of the landing zone. It must offer the models in model_deployments."
  default     = "swedencentral"
}

variable "name_prefix" {
  type        = string
  description = "Short prefix of every resource name (3 to 7 lowercase letters or digits)."
  default     = "alz"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,6}$", var.name_prefix))
    error_message = "name_prefix is 3 to 7 lowercase letters or digits, starting with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Environment name, part of every resource name (dev, test, prod)."
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,5}$", var.environment))
    error_message = "environment is 2 to 6 lowercase letters or digits, starting with a letter."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags on every resource."
  default     = {}
}

variable "allowed_ip_ranges" {
  type        = list(string)
  description = "Public IP ranges (CIDR) allowed to reach the services. Empty: all networks, Entra ID still required."
  default     = []
}

variable "log_analytics_retention_days" {
  type        = number
  description = "Days Log Analytics keeps the logs."
  default     = 30

  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "log_analytics_retention_days is between 30 and 730."
  }
}

variable "model_deployments" {
  type = map(object({
    model_name    = string
    model_version = string
    sku           = optional(string, "GlobalStandard")
    capacity      = optional(number, 10)
  }))
  description = "Model deployments on the Foundry account, by deployment name. capacity is in thousands of tokens per minute."
  default = {
    "gpt-5.4-mini" = {
      model_name    = "gpt-5.4-mini"
      model_version = "2026-03-17"
    }
  }

  validation {
    condition     = length(var.model_deployments) > 0
    error_message = "model_deployments holds at least one deployment."
  }
}

variable "project_user_principals" {
  type = map(object({
    principal_id   = string
    principal_type = optional(string, "Group")
  }))
  description = "Entra groups (or users) that use the Foundry project: they get the Foundry User role on the account. Keep real object IDs out of committed files."
  default     = {}

  validation {
    condition     = alltrue([for p in values(var.project_user_principals) : contains(["Group", "User", "ServicePrincipal"], p.principal_type)])
    error_message = "principal_type is Group, User or ServicePrincipal."
  }
}

variable "enable_telemetry" {
  type        = bool
  description = "Send the AVM modules' usage telemetry to Microsoft (https://aka.ms/avm/telemetryinfo)."
  default     = false
}
