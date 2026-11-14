# The SQL job's three tables in the platform's workspace and the Direct DCR that writes them
# (docs/learn/logs-ingestion-api.md). The columns are the rows job/sql_job.py builds; change both together.

locals {
  common_columns = [
    { name = "TimeGenerated", type = "datetime" },
    { name = "Env", type = "string" },
    { name = "Database", type = "string" },
    { name = "RunId", type = "string" },
  ]
  streams = {
    OdooQueue = concat(local.common_columns, [
      { name = "Check", type = "string" },
      { name = "State", type = "string" },
      { name = "Channel", type = "string" },
      { name = "Model", type = "string" },
      { name = "Method", type = "string" },
      { name = "Count", type = "long" },
      { name = "OldestAgeSec", type = "real" },
      { name = "Rows", type = "long" },
      { name = "Bytes", type = "long" },
    ])
    OdooCron = concat(local.common_columns, [
      { name = "CronId", type = "int" },
      { name = "CronName", type = "string" },
      { name = "IntervalSec", type = "long" },
      { name = "NextCall", type = "datetime" },
      { name = "LastCall", type = "datetime" },
      { name = "OverdueSec", type = "real" },
      { name = "FailureCount", type = "int" },
    ])
    OdooHeartbeat = concat(local.common_columns, [
      { name = "JobVersion", type = "string" },
      { name = "DbMs", type = "real" },
      { name = "DurationMs", type = "real" },
      { name = "QueueRows", type = "int" },
      { name = "CronRows", type = "int" },
      { name = "TableRows", type = "int" },
    ])
    # round 2 (docs/specs/round-2.md): the table statistics of the SQL job, the log reader's counts
    OdooTables = concat(local.common_columns, [
      { name = "TableName", type = "string" },
      { name = "LiveRows", type = "long" },
      { name = "DeadRows", type = "long" },
      { name = "DeadPct", type = "real" },
      { name = "LastAutovacuum", type = "datetime" },
      { name = "AutovacuumCount", type = "long" },
      { name = "Bytes", type = "long" },
    ])
    OdooLog = concat(local.common_columns, [
      { name = "File", type = "string" },
      { name = "Kind", type = "string" },
      { name = "Count", type = "long" },
      { name = "FirstAt", type = "datetime" },
      { name = "LastAt", type = "datetime" },
      { name = "Sample", type = "string" },
    ])
  }
}

resource "azapi_resource" "table" {
  for_each  = local.streams
  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = "${each.key}_CL"
  parent_id = data.azurerm_log_analytics_workspace.platform.id
  body = {
    properties = {
      plan   = "Analytics"
      schema = { name = "${each.key}_CL", columns = each.value }
    }
  }
}

resource "azapi_resource" "dcr" {
  type      = "Microsoft.Insights/dataCollectionRules@2023-03-11"
  name      = "erp-mgmt-obs-sqljob-dcr"
  parent_id = data.azurerm_resource_group.track.id
  location  = local.location
  tags      = local.tags
  body = {
    kind = "Direct"
    properties = {
      description        = "The observability track's SQL job: Odoo's queue_job and ir_cron, every 5 min"
      streamDeclarations = { for k, cols in local.streams : "Custom-${k}" => { columns = cols } }
      destinations = {
        logAnalytics = [{ name = "platform", workspaceResourceId = data.azurerm_log_analytics_workspace.platform.id }]
      }
      dataFlows = [for k, _ in local.streams : {
        streams      = ["Custom-${k}"]
        destinations = ["platform"]
        transformKql = "source"
        outputStream = "Custom-${k}_CL"
      }]
    }
  }
  response_export_values = {
    immutable_id = "properties.immutableId"
    endpoint     = "properties.endpoints.logsIngestion"
  }
  depends_on = [azapi_resource.table]
}
