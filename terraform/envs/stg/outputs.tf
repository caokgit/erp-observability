output "obs_monitor_password" {
  description = "For sql/scram.py and the A1 check; never printed: terraform output -raw obs_monitor_password | ..."
  value       = random_password.obs_monitor.result
  sensitive   = true
}
output "job_name" {
  value = module.sql_job.job_name
}
output "log_rules" {
  value = module.alerts.log_rules
}
output "metric_rules" {
  value = module.alerts.metric_rules
}
output "log_job_name" {
  value = module.sql_job.log_job_name
}
