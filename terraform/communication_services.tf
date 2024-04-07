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