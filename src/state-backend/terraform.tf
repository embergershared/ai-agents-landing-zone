terraform {
  required_version = ">= 1.12, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # The bootstrap keeps its own small state locally, since it creates the backend the other root
  # modules use. Its path is set at init, outside the working copy (docs/state-backend.md):
  #   terraform init -backend-config="path=<folder outside the repository>/terraform.tfstate"
  backend "local" {}
}

# The subscription comes from ARM_SUBSCRIPTION_ID, never from a committed file. No storage
# account key is ever used: the storage data plane is reached with Entra ID only.
provider "azurerm" {
  features {}
  storage_use_azuread = true
}
