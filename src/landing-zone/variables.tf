variable "location" {
  type        = string
  description = "Azure region of the landing zone. It must offer the models in model_deployments."
  default     = "swedencentral"
}

variable "name_prefix" {
  type        = string
  description = "Prefix of every resource name. Names keep its letters and digits in lowercase, turn other characters into hyphens, and shorten it to fit each type's maximum length."
  default     = "alz"

  validation {
    condition     = length(regexall("[a-zA-Z0-9]", var.name_prefix)) >= 3
    error_message = "name_prefix needs at least 3 letters or digits."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (dev, test, prod), part of every resource name, made compliant like name_prefix. Tags and App Configuration labels use it as written."
  default     = "dev"

  validation {
    condition     = length(regexall("[a-zA-Z0-9]", var.environment)) >= 2
    error_message = "environment needs at least 2 letters or digits."
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

variable "deploy_agent_service_dependencies" {
  type        = bool
  description = "Deploy the Foundry Agent Service with its own Cosmos DB, AI Search and Storage (standard setup). Off: agents use the basic setup (Microsoft-managed storage)."
  default     = true
}

variable "existing_agent_service_dependencies" {
  type = object({
    cosmos_db_resource_id       = string
    ai_search_resource_id       = string
    storage_account_resource_id = string
  })
  description = "Reuse a dedicated existing set of Agent Service dependencies instead of creating one. Used only when deploy_agent_service_dependencies is true."
  default     = null
}

variable "agent_cosmos_db_serverless" {
  type        = bool
  description = "Cosmos DB for the Agent Service in serverless mode (pay per request). Off: provisioned throughput, at least 3000 RU/s."
  default     = true
}

variable "agent_cosmos_db_total_throughput_limit" {
  type        = number
  description = "Provisioned mode only: the account's total throughput limit in RU/s (-1 for no limit). The Agent Service needs at least 3000."
  default     = -1

  validation {
    condition     = var.agent_cosmos_db_total_throughput_limit == -1 || var.agent_cosmos_db_total_throughput_limit >= 3000
    error_message = "agent_cosmos_db_total_throughput_limit is -1 (no limit) or at least 3000 RU/s."
  }
}

variable "agent_search_sku" {
  type        = string
  description = "AI Search SKU for the Agent Service."
  default     = "basic"

  validation {
    condition     = contains(["basic", "standard", "standard2", "standard3"], var.agent_search_sku)
    error_message = "agent_search_sku is basic, standard, standard2 or standard3."
  }
}

variable "agent_search_replica_count" {
  type        = number
  description = "AI Search replicas for the Agent Service (2 or more for a read SLA)."
  default     = 1
}

variable "deploy_workload" {
  type        = bool
  description = "Deploy the workload group: App Configuration with the landing zone's endpoints, Container Registry, Container Apps environment, the applications' managed identity, Key Vault, and the applications' own AI Search and Storage (separate from the Agent Service's)."
  default     = true
}

# Replaced by deploy_workload. Kept so that a tfvars file still setting them fails the plan
# instead of being ignored with a warning.
variable "deploy_application_platform" {
  type        = bool
  description = "Removed: use deploy_workload."
  default     = null

  validation {
    condition     = var.deploy_application_platform == null
    error_message = "deploy_application_platform is replaced by deploy_workload, one switch for the whole workload group. Remove it from the tfvars file."
  }
}

variable "deploy_application_data" {
  type        = bool
  description = "Removed: use deploy_workload."
  default     = null

  validation {
    condition     = var.deploy_application_data == null
    error_message = "deploy_application_data is replaced by deploy_workload, one switch for the whole workload group. Remove it from the tfvars file."
  }
}

variable "app_configuration_sku" {
  type        = string
  description = "App Configuration SKU."
  default     = "standard"

  validation {
    condition     = contains(["free", "developer", "standard", "premium"], var.app_configuration_sku)
    error_message = "app_configuration_sku is free, developer, standard or premium."
  }
}

variable "container_registry_sku" {
  type        = string
  description = "Container Registry SKU."
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.container_registry_sku)
    error_message = "container_registry_sku is Basic, Standard or Premium."
  }
}

variable "app_search_sku" {
  type        = string
  description = "SKU of the applications' AI Search."
  default     = "basic"

  validation {
    condition     = contains(["basic", "standard", "standard2", "standard3"], var.app_search_sku)
    error_message = "app_search_sku is basic, standard, standard2 or standard3."
  }
}

variable "app_settings_writer_principals" {
  type = map(object({
    principal_id   = string
    principal_type = optional(string, "User")
  }))
  description = "People or groups that run Terraform from a workstation: App Configuration Data Owner, to write the settings. The pipeline identity gets the role from src/state-backend. Keep real object IDs out of committed files."
  default     = {}

  validation {
    condition     = alltrue([for p in values(var.app_settings_writer_principals) : contains(["Group", "User", "ServicePrincipal"], p.principal_type)])
    error_message = "principal_type is Group, User or ServicePrincipal."
  }
}

variable "search_location" {
  type        = string
  description = "Region of the two AI Search services (the Agent Service's and the applications'), when it isn't location: for a region without AI Search capacity. Null: location."
  default     = null
}
