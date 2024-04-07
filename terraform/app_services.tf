resource "azurerm_linux_web_app" "airlog-linux-app" {
  name                = "airlog-linux-app"
  resource_group_name = azurerm_resource_group.airlog-rg.name
  location            = azurerm_service_plan.airlog-sp.location
  service_plan_id     = azurerm_service_plan.airlog-sp.id

  # Configure Docker settings
  app_settings = {
    DOCKER_REGISTRY_SERVER_URL          = azurerm_container_registry.airlog-acr.login_server
    DOCKER_REGISTRY_SERVER_USERNAME     = azurerm_container_registry.airlog-acr.admin_username
    DOCKER_REGISTRY_SERVER_PASSWORD     = azurerm_container_registry.airlog-acr.admin_password
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    API_KEY                             = var.api_key
  }

  # Configure the app to use the custom container
  site_config {
    always_on = "true"

    application_stack {
      docker_image     = "${azurerm_container_registry.airlog-acr.login_server}/${local.image_name}"
      docker_image_tag = local.image_tag
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    environment = "dev"
  }

  depends_on = [
    azurerm_container_registry.airlog-acr,
    azurerm_service_plan.airlog-sp
  ]
}

resource "azurerm_service_plan" "airlog-sp" {
  name                = "airlog-sp"
  resource_group_name = azurerm_resource_group.airlog-rg.name
  location            = azurerm_resource_group.airlog-rg.location
  os_type             = "Linux"
  sku_name            = "B1"

  tags = {
    environment = "dev"
  }
}
