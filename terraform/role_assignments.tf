# Assign the ACR pull role to the web app
resource "azurerm_role_assignment" "airlog-acrpull-role-assignment-web-app" {
  scope                = azurerm_container_registry.airlog-acr.id
  role_definition_name = "ACRPull"
  principal_id         = azurerm_linux_web_app.airlog-linux-app.identity[0].principal_id

  depends_on = [
    azurerm_container_registry.airlog-acr
  ]
}

# Assign the ACR pull role to the container app
resource "azurerm_role_assignment" "airlog-container-app" {
  scope                = azurerm_container_registry.airlog-acr.id
  role_definition_name = "acrpull"
  principal_id         = azurerm_user_assigned_identity.airlog-container-app.principal_id

  depends_on = [
    azurerm_user_assigned_identity.airlog-container-app
  ]
}