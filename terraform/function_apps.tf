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