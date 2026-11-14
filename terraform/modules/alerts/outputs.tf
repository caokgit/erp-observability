output "log_rules" {
  value = { for id, r in azurerm_monitor_scheduled_query_rules_alert_v2.log : id => { name = r.name, enabled = r.enabled } }
}
output "metric_rules" {
  value = { for id, r in azurerm_monitor_metric_alert.metric : id => { name = r.name, enabled = r.enabled } }
}
output "queries" {
  description = "The rendered queries, to compare with kql/backtest.py --print"
  value       = local.queries
}
