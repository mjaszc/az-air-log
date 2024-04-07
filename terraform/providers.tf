terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.94.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "1.12.1"
    }
  }
}

# Define providers
provider "azurerm" {
  features {  
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "azapi" {
}