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

data "azurerm_container_registry" "acr-name" {
  name                = azurerm_container_registry.airlog-acr.name
  resource_group_name = azurerm_resource_group.airlog-rg.name
}

# Assign the ACR pull role to the web app
resource "azurerm_role_assignment" "airlog-acrpull-role-assignment-web-app" {
  scope                = azurerm_container_registry.airlog-acr.id
  role_definition_name = "ACRPull"
  principal_id         = azurerm_linux_web_app.airlog-linux-app.identity[0].principal_id

  depends_on = [
    azurerm_container_registry.airlog-acr
  ]
}

# Local container image
locals {
  image_name = "az-air-log"
  image_tag  = "latest"
}

# Create a docker image
resource "null_resource" "docker_image" {
  triggers = {
    image_name         = local.image_name
    image_tag          = local.image_tag
    registry_name      = "${azurerm_container_registry.airlog-acr.name}"
    dockerfile_path    = "../app/Dockerfile"
    dockerfile_context = "../app"
    # Trigger the build when the Dockerfile or any file in the app directory changes
    dir_sha1           = sha1(join("", [for f in fileset("../", "../app/*") : filesha1(f)]))
  }

  provisioner "local-exec" {
    command     = "./scripts/build_acr.sh ${self.triggers.image_name} ${self.triggers.image_tag} ${self.triggers.registry_name} ${self.triggers.dockerfile_path} ${self.triggers.dockerfile_context}"
    interpreter = ["bash", "-c"]
  }

  depends_on = [
    azurerm_container_registry.airlog-acr
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

  depends_on = [
    azurerm_resource_group.airlog-rg
  ]
}

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

resource "azurerm_container_app_environment" "airlog-container-app-env" {
  name                       = "airlog-container-app-env"
  location                   = azurerm_resource_group.airlog-rg.location
  resource_group_name        = azurerm_resource_group.airlog-rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.airlog-law.id
}
 
resource "azurerm_user_assigned_identity" "airlog-container-app" {
  location            = azurerm_resource_group.airlog-rg.location
  name                = "airlog-container-app"
  resource_group_name = azurerm_resource_group.airlog-rg.name
}

resource "azurerm_role_assignment" "airlog-container-app" {
  scope                = azurerm_container_registry.airlog-acr.id
  role_definition_name = "acrpull"
  principal_id         = azurerm_user_assigned_identity.airlog-container-app.principal_id

  depends_on = [
    azurerm_user_assigned_identity.airlog-container-app
  ]
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

resource "azurerm_application_insights" "airlog-app-insights" {
  name                = "airlog-app-insights"
  location            = azurerm_resource_group.airlog-rg.location
  resource_group_name = azurerm_resource_group.airlog-rg.name
  application_type    = "web"
}

resource "azurerm_linux_function_app" "airlog-linux-function-app" {
  name                = "airlog-linux-function-app"
  resource_group_name = azurerm_resource_group.airlog-rg.name
  location            = azurerm_resource_group.airlog-rg.location

  storage_account_name       = azurerm_storage_account.airlog-storage-account.name
  storage_account_access_key = azurerm_storage_account.airlog-storage-account.primary_access_key
  service_plan_id            = azurerm_service_plan.airlog-sp.id

  # Setting environment variables
  app_settings = {
    API_KEY                        = var.api_key
    AZURE_EMAIL_CONNECTION_STRING  = azurerm_communication_service.airlog-communication-service.primary_connection_string
    AZURE_EMAIL_RECIPIENT          = var.azure_email_recipient
    APPINSIGHTS_INSTRUMENTATIONKEY = azurerm_application_insights.airlog-app-insights.instrumentation_key
  }

  site_config {
    application_stack {
      python_version = "3.10"
    }

    cors {
      allowed_origins = [
        "https://portal.azure.com",
        "https://airlog-linux-app.azurewebsites.net",
        "http://127.0.0.1:5000", // For local testing
        azurerm_container_app.airlog-container-app.ingress[0].fqdn // adding the URL of the container app as an allowed origin
      ]
    }
  }

  tags = {
    environment = "prod"
  }

  depends_on = [
    azurerm_storage_account.airlog-storage-account,
    azurerm_service_plan.airlog-sp,
    azurerm_communication_service.airlog-communication-service,
    azurerm_email_communication_service.airlog-email-communication-service,
    azapi_resource.email-service-domain, azurerm_container_app.airlog-container-app
  ]
}

resource "azurerm_communication_service" "airlog-communication-service" {
  name                = "airlog-communication-service"
  resource_group_name = azurerm_resource_group.airlog-rg.name
  data_location       = "Europe"

  tags = {
    environment = "prod"
  }
}

resource "azurerm_email_communication_service" "airlog-email-communication-service" {
  name                = "airlog-email-communication-service"
  resource_group_name = azurerm_resource_group.airlog-rg.name
  data_location       = "Europe"

  tags = {
    environment = "prod"
  }
}

resource "azapi_resource" "email-service-domain" {
  type      = "Microsoft.Communication/emailServices/domains@2023-04-01-preview"
  name      = "AzureManagedDomain"
  location  = "Global"
  parent_id = azurerm_email_communication_service.airlog-email-communication-service.id

  tags = {
    environment = "prod"
  }

  body = jsonencode({
    properties = {
      domainManagement       = "AzureManaged"
      userEngagementTracking = "Disabled"
    }
  })
}