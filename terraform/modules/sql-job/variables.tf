variable "env" {
  description = "dev or stg: the OBS_ENV of every row"
  type        = string
}

variable "name_prefix" {
  description = "For the identity and the job, e.g. erp-dev-obs"
  type        = string
}

variable "resource_group_name" {
  description = "The track's resource group in the environment's subscription"
  type        = string
}

variable "location" {
  type = string
}

variable "environment_id" {
  description = "The Container Apps environment the job runs in (D5)"
  type        = string
}

variable "workload_profile_name" {
  type    = string
  default = "Consumption"
}

variable "registry" {
  description = "The stg shared registry (D12): id and login server"
  type        = object({ id = string, login_server = string })
}

variable "image_tag" {
  description = "Tag of obs/sql-job in the registry; empty: no job yet (the image is pushed after the first apply)"
  type        = string
  default     = ""
}

variable "schedule_enabled" {
  description = "true: every 5 min; false: the job stays, started only by hand (drills, A5)"
  type        = bool
  default     = true
}

variable "dcr" {
  description = "The data collection rule: id, immutable id, logs ingestion endpoint"
  type        = object({ id = string, immutable_id = string, endpoint = string })
}

variable "database" {
  description = "The Postgres server's FQDN and the Odoo database"
  type        = object({ host = string, name = string })
}

variable "password" {
  description = "obs_monitor's password (sql/obs_monitor.sql gets its SCRAM verifier)"
  type        = string
  sensitive   = true
}

variable "log_storage_name" {
  description = "Round 2's log reader: the environment's storage of the Odoo share; empty: no log reader"
  type        = string
  default     = ""
}

variable "log_mount_options" {
  description = "SMB mount options of the log reader's volume (\"ro\" where the storage is read-write)"
  type        = string
  default     = ""
}

variable "tags" {
  type = map(string)
}
