resource "azurerm_user_assigned_identity" "airlog-container-app" {
  location            = azurerm_resource_group.airlog-rg.location
  name                = "airlog-container-app"
  resource_group_name = azurerm_resource_group.airlog-rg.name
}