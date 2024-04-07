resource "azurerm_container_registry" "airlog-acr" {
  name                = "airlogacr"
  resource_group_name = azurerm_resource_group.airlog-rg.name
  location            = azurerm_resource_group.airlog-rg.location
  sku                 = "Basic"
  admin_enabled       = true

  tags = {
    environment = "dev"
  }
}

data "azurerm_container_registry" "acr-name" {
  name                = azurerm_container_registry.airlog-acr.name
  resource_group_name = azurerm_resource_group.airlog-rg.name
}

resource "azurerm_container_group" "airlog-aci" {
  name                = "airlog-test-aci"
  location            = azurerm_resource_group.airlog-rg.location
  resource_group_name = azurerm_resource_group.airlog-rg.name
  ip_address_type     = "Public"
  dns_name_label      = "air-log"
  os_type             = "Linux"

  image_registry_credential {
    username = azurerm_container_registry.airlog-acr.admin_username
    password = azurerm_container_registry.airlog-acr.admin_password
    server   = azurerm_container_registry.airlog-acr.login_server
  }

  container {
    name   = "airlog-container"
    image  = "${azurerm_container_registry.airlog-acr.login_server}/${local.image_name}:${local.image_tag}"
    cpu    = "0.5"
    memory = "1.5"

    ports {
      port     = 8000
      protocol = "TCP"
    }

    environment_variables = {
      API_KEY = var.api_key
    }
  }

  tags = {
    environment = "dev"
  }

  depends_on = [
    azurerm_container_registry.airlog-acr
  ]
}

resource "azurerm_container_app_environment" "airlog-container-app-env" {
  name                       = "airlog-container-app-env"
  location                   = azurerm_resource_group.airlog-rg.location
  resource_group_name        = azurerm_resource_group.airlog-rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.airlog-law.id
}

resource "azurerm_container_app" "airlog-container-app" {
  name                         = "airlog-container-app"
  container_app_environment_id = azurerm_container_app_environment.airlog-container-app-env.id
  resource_group_name          = azurerm_resource_group.airlog-rg.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.airlog-container-app.id]
  }
 
  registry {
    server   = azurerm_container_registry.airlog-acr.login_server
    identity = azurerm_user_assigned_identity.airlog-container-app.id
  }

  ingress {
    external_enabled = true
    target_port = 8000
    traffic_weight {
      percentage = 100
      latest_revision = true
    }
  }

  template {
    container {
      name   = "airlog-container"
      image  = "${azurerm_container_registry.airlog-acr.login_server}/${local.image_name}:${local.image_tag}"
      cpu    = "0.75"
      memory = "1.5Gi"

      env {
        name  = "API_KEY"
        value = var.api_key
      }
    }
  }

  tags = {
    environment = "prod"
  }

  depends_on = [
    azurerm_container_registry.airlog-acr,
    azurerm_user_assigned_identity.airlog-container-app
  ]
}