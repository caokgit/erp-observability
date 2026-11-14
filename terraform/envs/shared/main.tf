# What dev and stg share, in the track's management-sub resource group (docs/specs/round-1.md#terraform):
# the four action groups, page and ticket per environment, and a Logic App per environment for the Teams card (#routing), the job's three tables and its data collection rule (#the-sql-job).
# The resource group itself holds the state storage, so it is created and removed by terraform/state-storage.sh.

locals {
  location = "southeastasia"
  tags     = { owner = "observability-track", env = "shared" } # nothing naming the repo (AGENTS.md)
}

data "azurerm_resource_group" "track" {
  name = "erp-mgmt-obs-rg"
}

data "azurerm_log_analytics_workspace" "platform" {
  name                = "platform-logs"
  resource_group_name = "monitor-rg"
}

locals {
  # short names: 12 characters at most
  groups = { for p in setproduct(["dev", "stg"], ["page", "ticket"]) : "${p[0]}-${p[1]}" => {
  env = p[0], group = p[1], short = "obs-${p[0]}-${p[1] == "page" ? "page" : "tkt"}" } }
}

resource "azurerm_monitor_action_group" "this" {
  for_each            = local.groups
  name                = "erp-mgmt-obs-${each.key}-ag"
  short_name          = each.value.short
  resource_group_name = data.azurerm_resource_group.track.name
  location            = "global"
  tags                = local.tags

  logic_app_receiver {
    name                    = "teams-${each.value.env}"
    resource_id             = azurerm_logic_app_workflow.teams[each.value.env].id
    callback_url            = azurerm_logic_app_trigger_http_request.alert[each.value.env].callback_url
    use_common_alert_schema = true
  }
}

# The Teams workflows post the request body as an Adaptive Card and are shared with other senders, so each
# environment's Logic App turns the alert (common alert schema) into the card and posts it (#routing, D11).
resource "azurerm_logic_app_workflow" "teams" {
  for_each            = toset(["dev", "stg"])
  name                = "erp-mgmt-obs-${each.key}-teams-logic"
  resource_group_name = data.azurerm_resource_group.track.name
  location            = local.location
  tags                = local.tags
}

resource "azurerm_logic_app_trigger_http_request" "alert" {
  for_each     = azurerm_logic_app_workflow.teams
  name         = "alert"
  logic_app_id = each.value.id
  schema       = jsonencode({ type = "object" })
}

# A ticket (Sev3) that resolves posts no card; a page's resolve still does, so whoever was paged sees it end
# (docs/specs/round-6.md#4-tickets-post-no-resolve-card). On per environment, dev before stg (var.quiet_resolves).
locals {
  card_post = { for env in ["dev", "stg"] : env => {
    type     = "Http"
    runAfter = {}
    inputs = {
      method  = "POST"
      uri     = var.alert_routes[env].teams_webhook
      headers = { "Content-Type" = "application/json" }
      body    = jsondecode(file("${path.module}/../../teams/alert-card.json"))
    }
  } }
}

resource "azurerm_logic_app_action_custom" "post" {
  for_each     = azurerm_logic_app_workflow.teams
  name         = "post-card"
  logic_app_id = each.value.id
  body = contains(var.quiet_resolves, each.key) ? jsonencode({
    type     = "If"
    runAfter = {}
    expression = { or = [
      { not = { equals = ["@triggerBody()?['data']?['essentials']?['monitorCondition']", "Resolved"] } },
      { not = { equals = ["@triggerBody()?['data']?['essentials']?['severity']", "Sev3"] } },
    ] }
    actions = { post = local.card_post[each.key] }
    else    = { actions = {} }
  }) : jsonencode(local.card_post[each.key])
}
