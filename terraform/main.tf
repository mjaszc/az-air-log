terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.94.0"
    }
  }
}

# Define provider
provider "azurerm" {
  features {}
}

# Create a resource group
resource "azurerm_resource_group" "airlog-rg" {
  name     = "airlog-rg"
  location = "West Europe"
}

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

# Sleep for 30 seconds to wait for the ACR to be created
resource "time_sleep" "acr-wait" {
  create_duration = "30s"

  depends_on = [azurerm_container_registry.airlog-acr]
}

# Assign the ACR pull role to the web app
resource "azurerm_role_assignment" "airlog-acrpull-role-assignment" {
  scope                = azurerm_container_registry.airlog-acr.id
  role_definition_name = "ACRPull"
  principal_id         = azurerm_linux_web_app.airlog-linux-app.identity[0].principal_id

  depends_on = [azurerm_linux_web_app.airlog-linux-app, azurerm_container_registry.airlog-acr]
}

# Local container image
locals {
  image_name = "az-air-log"
  image_tag  = "latest"
}

# Create a docker image
resource "terraform_data" "docker_image" {
  triggers_replace = {
    image_name         = local.image_name
    image_tag          = local.image_tag
    registry_name      = azurerm_container_registry.airlog-acr.name
    dockerfile_path    = "../app/Dockerfile"
    dockerfile_context = "../app"
    dir_sha1           = sha1(join("", [for f in fileset("../", "../app/*") : filesha1(f)]))
  }

  provisioner "local-exec" {
    command     = "./scripts/build_acr.sh ${self.triggers_replace.image_name} ${self.triggers_replace.image_tag} ${azurerm_container_registry.airlog-acr.name} ${self.triggers_replace.dockerfile_path} ${self.triggers_replace.dockerfile_context}"
    interpreter = ["bash", "-c"]
  }

  depends_on = [time_sleep.acr-wait]
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

  depends_on = [azurerm_resource_group.airlog-rg]
}

resource "azurerm_linux_web_app" "airlog-linux-app" {
  name                = "airlog-linux-app"
  resource_group_name = azurerm_resource_group.airlog-rg.name
  location            = azurerm_service_plan.airlog-sp.location
  service_plan_id     = azurerm_service_plan.airlog-sp.id

  # Configure Docker settings
  app_settings = {
    DOCKER_REGISTRY_SERVER_URL          = "${azurerm_container_registry.airlog-acr.login_server}"
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

  depends_on = [azurerm_container_registry.airlog-acr, azurerm_service_plan.airlog-sp, terraform_data.docker_image]
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

  depends_on = [azurerm_container_registry.airlog-acr, terraform_data.docker_image]
}

resource "azurerm_storage_account" "airlog-storage-account" {
  name                     = "airlogstorageaccount"
  resource_group_name      = azurerm_resource_group.airlog-rg.name
  location                 = azurerm_resource_group.airlog-rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  depends_on = [azurerm_resource_group.airlog-rg]
}

resource "azurerm_linux_function_app" "airlog-linux-function-app" {
  name                = "airlog-linux-function-app"
  resource_group_name = azurerm_resource_group.airlog-rg.name
  location            = azurerm_resource_group.airlog-rg.location

  storage_account_name       = azurerm_storage_account.airlog-storage-account.name
  storage_account_access_key = azurerm_storage_account.airlog-storage-account.primary_access_key 
  service_plan_id            = azurerm_service_plan.airlog-sp.id

  site_config {
    application_stack {
      python_version = "3.10"
    }
  }

  depends_on = [azurerm_storage_account.airlog-storage-account, azurerm_service_plan.airlog-sp]
}