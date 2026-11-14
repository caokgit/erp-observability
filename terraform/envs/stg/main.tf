# Round 1 on stg (docs/specs/round-1.md#terraform): the environment real users work in (D1), rehearsed on dev first.
# Creates the track's stg resource group, the SQL job with its identity and the obs_monitor password, and stg's rules
# (enabled). stg's database lives on the prd server, read through the prd provider. Data sources only (D7).

locals {
  env      = "stg"
  location = "southeastasia"
  database = "erp-stg"
  tags     = { owner = "observability-track", env = local.env } # nothing naming the repo (AGENTS.md)
  shared   = data.terraform_remote_state.shared.outputs
}

data "terraform_remote_state" "shared" {
  backend = "azurerm"
  config = {
    subscription_id      = var.subscription_ids["management"]
    resource_group_name  = var.state.resource_group
    storage_account_name = var.state.account
    container_name       = var.state.container
    key                  = "shared.tfstate"
    use_azuread_auth     = true
  }
}

# The platform's resources, read only
data "azurerm_postgresql_flexible_server" "odoo" {
  provider            = azurerm.prd
  name                = var.pg_server.name
  resource_group_name = var.pg_server.resource_group
}

data "azurerm_container_app" "odoo" {
  for_each            = { for i, a in var.apps : "app${i + 1}" => a }
  name                = each.value.name
  resource_group_name = each.value.resource_group
}

data "azurerm_container_app_environment" "job" {
  name                = var.job_environment.name
  resource_group_name = var.job_environment.resource_group
}

data "azurerm_container_registry" "shared" {
  name                = var.registry.name
  resource_group_name = var.registry.resource_group
}

# The track's own
resource "azurerm_resource_group" "track" {
  name     = "erp-stg-obs-rg"
  location = local.location
  tags     = local.tags
}

resource "random_password" "obs_monitor" {
  length  = 32
  special = false # sql/scram.py expects letters and digits
}

module "sql_job" {
  source              = "../../modules/sql-job"
  env                 = local.env
  name_prefix         = "erp-stg-obs"
  resource_group_name = azurerm_resource_group.track.name
  location            = local.location
  environment_id      = data.azurerm_container_app_environment.job.id
  registry            = { id = data.azurerm_container_registry.shared.id, login_server = data.azurerm_container_registry.shared.login_server }
  image_tag           = var.job_image_tag
  schedule_enabled    = var.job_schedule_enabled
  dcr                 = local.shared.dcr
  database            = { host = var.pg_server.fqdn, name = local.database }
  password            = random_password.obs_monitor.result
  log_storage_name    = var.log_storage.name
  log_mount_options   = var.log_storage.mount_options
  tags                = local.tags
}

module "alerts" {
  source              = "../../modules/alerts"
  providers           = { azurerm = azurerm.management }
  env                 = local.env
  resource_group_name = local.shared.resource_group_name
  location            = local.shared.location
  workspace_id        = local.shared.workspace_id
  action_group_ids    = local.shared.action_group_ids[local.env]
  targets             = { apps = [for a in var.apps : a.name], pg_server = var.pg_server.name, gateway = var.gateway.name, database_id = var.pg_database_id }
  app_ids             = { for k, a in data.azurerm_container_app.odoo : k => a.id }
  pg_server_id        = data.azurerm_postgresql_flexible_server.odoo.id
  enabled             = var.rules_enabled
  overrides           = var.rule_overrides
  tags                = local.tags
}
