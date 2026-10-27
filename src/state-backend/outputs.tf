output "resource_group_name" {
  description = "Resource group of the state backend."
  value       = azurerm_resource_group.state.name
}

output "storage_account_name" {
  description = "Storage account that holds the Terraform state."
  value       = azurerm_storage_account.state.name
}

output "containers" {
  description = "State container per environment."
  value       = { for env, c in azurerm_storage_container.state : env => c.name }
}

# The non-secret settings each environment's backend needs (docs/state-backend.md).
output "backend_config" {
  description = "Backend settings per environment, to write into <env>.backend.hcl."
  value = {
    for env, c in azurerm_storage_container.state : env => {
      resource_group_name  = azurerm_resource_group.state.name
      storage_account_name = azurerm_storage_account.state.name
      container_name       = c.name
      key                  = "landing-zone.tfstate"
      use_azuread_auth     = true
    }
  }
}
