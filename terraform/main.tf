resource "azurerm_storage_account" "airlog-storage-account" {
  name                     = "airlogstorageaccount"
  resource_group_name      = azurerm_resource_group.airlog-rg.name
  location                 = azurerm_resource_group.airlog-rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = "prod"
  }

  depends_on = [
    azurerm_resource_group.airlog-rg
  ]
}

resource "azurerm_log_analytics_workspace" "airlog-law" {
  name                = "airlog-law"
  location            = azurerm_resource_group.airlog-rg.location
  resource_group_name = azurerm_resource_group.airlog-rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}
 
resource "azurerm_application_insights" "airlog-app-insights" {
  name                = "airlog-app-insights"
  location            = azurerm_resource_group.airlog-rg.location
  resource_group_name = azurerm_resource_group.airlog-rg.name
  application_type    = "web"
}