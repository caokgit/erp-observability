# Names come from terraform/names.sh (names.auto.tfvars.json, committed: AGENTS.md#writing); never written in the code.

variable "subscription_ids" {
  type = map(string)
}
variable "pg_server" {
  type = object({ name = string, resource_group = string, fqdn = string, subscription = string })
}
variable "apps" {
  type = list(object({ name = string, resource_group = string }))
}
variable "job_environment" {
  type = object({ name = string, resource_group = string })
}
variable "registry" {
  type = object({ name = string, resource_group = string })
}
variable "gateway" {
  type = object({ name = string, resource_group = string })
}
variable "state" {
  description = "The track's state storage, for the shared root's outputs"
  type        = object({ resource_group = string, account = string, container = string })
}
variable "workspace_customer_id" {
  description = "Used by kql/backtest.py, not here"
  type        = string
}
variable "pg_servers_history" {
  description = "Used by kql/backtest.py, not here"
  type        = any
}

# Set per apply (Manual mode), never in a file
variable "job_image_tag" {
  description = "Tag of obs/sql-job to run; empty until the image is pushed"
  type        = string
  default     = ""
}
variable "job_schedule_enabled" {
  description = "dev: true while acceptance runs (A2), false otherwise and for the heartbeat drill (A5)"
  type        = bool
  default     = true
}
variable "rules_enabled" {
  description = "dev's rules run only during drills (docs/specs/round-1.md#routing)"
  type        = bool
  default     = false
}
variable "rule_overrides" {
  description = "Drills: per rule, enabled and lowered thresholds (see terraform/modules/alerts)"
  type = map(object({
    enabled   = optional(bool)
    params    = optional(map(string), {})
    threshold = optional(number)
    window    = optional(string) # a log rule's window and lookback, widened for a drill (Azure: at most P2D)
    lookback  = optional(string)
  }))
  default = {}
}

# Round 2 (docs/specs/round-2.md), set in deploy.auto.tfvars.json
variable "log_storage" {
  description = "The environment's storage of the Odoo share for the log reader, and its mount options; empty name: no log reader"
  type        = object({ name = string, mount_options = optional(string, "") })
  default     = { name = "" }
}
variable "pg_database_id" {
  description = "The Odoo database's oid (Query Store's DatabaseId), for Q1"
  type        = number
  default     = -1
}
