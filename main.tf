terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # BACKEND
  backend "azurerm" {
    resource_group_name  = "ghpro100-rg"
    storage_account_name = "ghpro100web"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = "1416f3d7-88c5-4438-8133-8dd3d4acad4c"
}

# EXISTING RESOURCE GROUP
data "azurerm_resource_group" "rg" {
  name = "ghpro100-rg"
}

# EXISTING STORAGE ACCOUNT
data "azurerm_storage_account" "storage" {
  name                = "ghpro100web"
  resource_group_name = data.azurerm_resource_group.rg.name
}

# STATIC WEBSITE (Terraform will manage this part)
resource "azurerm_storage_account_static_website" "website" {
  storage_account_id = data.azurerm_storage_account.storage.id

  index_document     = "index.html"
  error_404_document = "index.html"
}

# FRONT DOOR PROFILE
resource "azurerm_cdn_frontdoor_profile" "afd" {
  name                = "ghpro100-afd"
  resource_group_name = data.azurerm_resource_group.rg.name
  sku_name            = "Standard_AzureFrontDoor"
}

# FRONT DOOR ENDPOINT
resource "azurerm_cdn_frontdoor_endpoint" "endpoint" {
  name                     = "ghpro100-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd.id
}

# ORIGIN GROUP
resource "azurerm_cdn_frontdoor_origin_group" "origin_group" {
  name                     = "storage-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd.id

  load_balancing {}

  health_probe {
    protocol            = "Https"
    interval_in_seconds = 120
  }
}

# ORIGIN (STORAGE STATIC WEBSITE)
resource "azurerm_cdn_frontdoor_origin" "origin" {
  name                          = "storage-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.origin_group.id

  host_name          = data.azurerm_storage_account.storage.primary_web_host
  origin_host_header = data.azurerm_storage_account.storage.primary_web_host

  http_port  = 80
  https_port = 443

  certificate_name_check_enabled = true
}

# CUSTOM DOMAIN
resource "azurerm_cdn_frontdoor_custom_domain" "domain" {
  name                     = "ghpro100-domain"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.afd.id
  host_name                = "www.ghpro100.co.uk"

  tls {
    certificate_type = "ManagedCertificate"
  }
}

# ROUTE
resource "azurerm_cdn_frontdoor_route" "route" {
  name                          = "route-all"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.endpoint.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.origin_group.id

  cdn_frontdoor_origin_ids = [
    azurerm_cdn_frontdoor_origin.origin.id
  ]

  cdn_frontdoor_custom_domain_ids = [
    azurerm_cdn_frontdoor_custom_domain.domain.id
  ]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true

  link_to_default_domain = true
}