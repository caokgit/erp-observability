output "resource_group_name" {
  value = data.azurerm_resource_group.track.name
}
output "location" {
  value = local.location
}
output "workspace_id" {
  value = data.azurerm_log_analytics_workspace.platform.id
}
output "action_group_ids" {
  value = { for env in ["dev", "stg"] : env => {
  for g in ["page", "ticket"] : g => azurerm_monitor_action_group.this["${env}-${g}"].id } }
}
output "dcr" {
  value = {
    id           = azapi_resource.dcr.id
    immutable_id = azapi_resource.dcr.output.immutable_id
    endpoint     = azapi_resource.dcr.output.endpoint
  }
}
output "tables" {
  value = [for t in azapi_resource.table : t.name]
}
