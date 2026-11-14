output "identity" {
  value = { id = azurerm_user_assigned_identity.job.id, principal_id = azurerm_user_assigned_identity.job.principal_id }
}
output "log_job_name" {
  value = try(azurerm_container_app_job.log[0].name, null)
}
output "job_name" {
  value = try(azurerm_container_app_job.sql[0].name, null)
}
