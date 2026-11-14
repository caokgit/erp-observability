# Round 1's alert rules for one environment (docs/specs/round-1.md#signals): the log rules of kql/rules.json and the
# metric rules M1 to M5. Each log rule's query is rendered as kql/backtest.py renders it (keep the two in step):
# targets, time range and parameters as let statements, then the function files and the rule's file, their comment
# lines dropped: the files' comments name repo paths, and nothing naming the repo reaches Azure (AGENTS.md).

locals {
  kql_dir = "${path.module}/../../../kql"
  catalog = jsondecode(file("${local.kql_dir}/rules.json")).rules

  target_lets = {
    Apps             = "dynamic(${jsonencode(var.targets.apps)})"
    Gateway          = jsonencode(var.targets.gateway)
    Servers          = "dynamic(${jsonencode([var.targets.pg_server])})"
    TargetDatabaseId = tostring(var.targets.database_id)
    TargetEnv        = jsonencode(var.env)
  }

  log_rules = {
    # a rule lists the environments it exists in (default both); "enabled_in": environments where it runs by default
    for id, r in local.catalog : id => merge(r, {
      params   = merge(r.params, try(var.overrides[id].params, {}))
      window   = coalesce(try(var.overrides[id].window, null), r.window)
      lookback = coalesce(try(var.overrides[id].lookback, null), r.lookback)
      enabled  = coalesce(try(var.overrides[id].enabled, null), contains(try(r.enabled_in, []), var.env) ? true : var.enabled)
    }) if contains(try(r.envs, ["dev", "stg"]), var.env)
  }

  queries = {
    for id, r in local.log_rules : id => join("\n", concat(
      [for k in sort(keys(local.target_lets)) : "let ${k} = ${local.target_lets[k]};"],
      ["let Start = ago(${r.lookback});", "let End = now();"],
      [for k in sort(keys(r.params)) : "let ${k} = ${r.params[k]};"],
      [for f in concat(r.functions, [r.file]) : replace(file("${local.kql_dir}/${f}"), "/(?m)^[ \\t]*//.*\\n/", "")],
    ))
  }

  severity = { page = 1, ticket = 3 }

  # The card's text (docs/specs/round-3.md#incident-response): what the rule means, then numbered first steps. It is the
  # rule's description in Azure, which the common alert schema carries to the Logic App's card; no repo path, no link.
  describe = { for id, r in local.log_rules : id => join("\n", concat(
    [r.about, "", "First steps:"], [for i, step in r.first_steps : "${i + 1}. ${step}"]
  )) }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "log" {
  for_each                = local.log_rules
  name                    = "obs-${var.env}-${each.key}"
  display_name            = "[${var.env}] ${each.key} ${each.value.title}"
  description             = local.describe[each.key]
  resource_group_name     = var.resource_group_name
  location                = var.location
  scopes                  = [var.workspace_id]
  enabled                 = each.value.enabled
  severity                = each.value.severity
  evaluation_frequency    = each.value.frequency
  window_duration         = each.value.window
  auto_mitigation_enabled = true
  tags                    = var.tags

  criteria {
    query                   = local.queries[each.key]
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    dynamic "dimension" {
      for_each = each.value.dimensions
      content {
        name     = dimension.value
        operator = "Include"
        values   = ["*"]
      }
    }

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups     = [var.action_group_ids[each.value.group]]
    custom_properties = { signal = each.key, env = var.env, severity = each.value.group }
  }
}

locals {
  # M1, M2: restarts per Odoo app; M3 to M5: the Postgres server. Thresholds from the spec, overridable for drills.
  # "about" and "first_steps": the card's text, as for the log rules in kql/rules.json.
  metric_rules = merge(
    { for name, id in var.app_ids : "M-restarts-${name}" => {
      signal = "M1, M2", title = "app restarted", scope = id, namespace = "Microsoft.App/containerApps",
      metric = "RestartCount", aggregation = "Total", operator = "GreaterThan", threshold = 0,
      window = "PT15M", frequency = "PT5M", group = "ticket",
      about  = "An Odoo app's container restarted in the last 15 minutes (a kill after failed health probes, a crash, or a new revision). While the web app restarts, its users get 502s for about 13 s.",
      first_steps = [
        "Open in Azure: which app (web or cron) and how many restarts.",
        "In the app's system log, read the reason at that time: ProbeFailure, a process exit, or a revision change (a deploy).",
        "Several in an hour: see L7 (a loop) and lock waits (L1).",
        "Next working day, unless a deploy explains it: the times and reasons to the ERP team.",
    ] } },
    {
      "M3" = { signal = "M3", title = "Postgres CPU at or above 90% over 15 min", scope = var.pg_server_id,
        namespace = "Microsoft.DBforPostgreSQL/flexibleServers", metric = "cpu_percent", aggregation = "Average",
        operator  = "GreaterThanOrEqual", threshold = 90, window = "PT15M", frequency = "PT5M", group = "ticket",
        about     = "The Postgres server that holds the Odoo database averaged 90 % CPU or more for 15 minutes. The server is shared with other databases; queries slow down for all of them.",
        first_steps = [
          "Open in Azure: the server's CPU over the last hours.",
          "Find the costliest queries of the hour in Query Store, and which database runs them (Q1 does it for Odoo's).",
          "Check scheduled tasks or imports running at that time.",
          "Next working day: to the platform team (the server) and the ERP team if Odoo's queries lead.",
      ] }
      "M4" = { signal = "M4", title = "Postgres storage above 85%", scope = var.pg_server_id,
        namespace = "Microsoft.DBforPostgreSQL/flexibleServers", metric = "storage_percent", aggregation = "Maximum",
        operator  = "GreaterThan", threshold = 85, window = "PT15M", frequency = "PT5M", group = "ticket",
        about     = "The Postgres server's storage is over 85 % used. Autogrow is on, but a full disk stops every database on the server.",
        first_steps = [
          "Open in Azure: storage used over the last days (a jump or a steady climb).",
          "Find the largest tables and their growth (the queue_job table grew to 1.38M rows in 2026-08).",
          "Check that the cleanup tasks run (L6) and dead rows are vacuumed (T1).",
          "Next working day: to the platform team.",
      ] }
      "M5" = { signal = "M5", title = "Postgres server not alive", scope = var.pg_server_id,
        namespace = "Microsoft.DBforPostgreSQL/flexibleServers", metric = "is_db_alive", aggregation = "Minimum",
        operator  = "LessThan", threshold = 1, window = "PT5M", frequency = "PT1M", group = "page",
        about     = "The Postgres server that holds the Odoo database did not answer Azure's liveness check for 5 minutes. Odoo and every other database on the server are down.",
        first_steps = [
          "Open in Azure: the server's state and Resource Health (a restart, maintenance, a failover).",
          "Check the Azure status page for the region.",
          "Expect 5xx on the web app (L2) and a missing heartbeat (H).",
          "Call the platform team now; tell the business channel that Odoo is down.",
      ] }
    },
  )
}

resource "azurerm_monitor_metric_alert" "metric" {
  for_each = local.metric_rules
  name     = "obs-${var.env}-${each.key}"
  description = join("\n", concat(
    [each.value.about, "", "First steps:"], [for i, step in each.value.first_steps : "${i + 1}. ${step}"]
  ))
  resource_group_name = var.resource_group_name
  scopes              = [each.value.scope]
  enabled             = coalesce(try(var.overrides[each.key].enabled, null), var.enabled)
  severity            = local.severity[each.value.group]
  frequency           = each.value.frequency
  window_size         = each.value.window
  auto_mitigate       = true
  tags                = var.tags

  criteria {
    metric_namespace = each.value.namespace
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = coalesce(try(var.overrides[each.key].threshold, null), each.value.threshold)
  }

  action {
    action_group_id = var.action_group_ids[each.value.group]
  }
}
