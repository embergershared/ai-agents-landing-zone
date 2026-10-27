terraform {
  required_version = ">= 1.12, < 2.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.12"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    # Used inside the Foundry module only; declared here so tests can mock them.
    modtm = {
      source  = "azure/modtm"
      version = "~> 0.4"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }

  # State in the storage account of src/state-backend, one container per environment:
  #   terraform init -backend-config=environments/<env>.backend.hcl
  backend "azurerm" {}
}

# The subscription comes from ARM_SUBSCRIPTION_ID; pipelines sign in through OIDC
# (ARM_USE_OIDC). No storage account key is used.
provider "azurerm" {
  storage_use_azuread = true

  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy = false
    }
    cognitive_account {
      purge_soft_delete_on_destroy = false
    }
  }
}

provider "azapi" {}
