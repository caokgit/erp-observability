terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.13" }
    random  = { source = "hashicorp/random", version = "~> 3.9" }
  }
  backend "azurerm" {} # backend.hcl, written by terraform/names.sh
}

# The stg subscription: the track's stg resource group, the job, its identity; the Odoo apps, their environment and
# the shared registry (D12) are read here too
provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_ids["stg"]
  resource_provider_registrations = "none"
}

# management-sub: the rules, beside the workspace (D6)
provider "azurerm" {
  alias = "management"
  features {}
  subscription_id                 = var.subscription_ids["management"]
  resource_provider_registrations = "none"
}

# prd-sub: the prd Postgres server holds stg's database (read only)
provider "azurerm" {
  alias = "prd"
  features {}
  subscription_id                 = var.subscription_ids["prd"]
  resource_provider_registrations = "none"
}
