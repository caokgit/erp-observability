terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.13" }
    random  = { source = "hashicorp/random", version = "~> 3.9" }
  }
  backend "azurerm" {} # backend.hcl, written by terraform/names.sh
}

# The dev subscription: the track's dev resource group, the job, its identity
provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_ids["dev"]
  resource_provider_registrations = "none"
}

# management-sub: the rules, beside the workspace (D6)
provider "azurerm" {
  alias = "management"
  features {}
  subscription_id                 = var.subscription_ids["management"]
  resource_provider_registrations = "none"
}

# stg-sub: the stg shared registry holds the image (D12)
provider "azurerm" {
  alias = "stg"
  features {}
  subscription_id                 = var.subscription_ids["stg"]
  resource_provider_registrations = "none"
}
