terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.13" }
    azapi   = { source = "Azure/azapi", version = "~> 2.13" }
  }
  backend "azurerm" {} # backend.hcl, written by terraform/names.sh
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_ids["management"]
  resource_provider_registrations = "none"
}

provider "azapi" {
  subscription_id = var.subscription_ids["management"]
}
