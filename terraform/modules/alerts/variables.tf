variable "env" {
  description = "dev or stg: in each rule's name and the TargetEnv of the SQL job's rows"
  type        = string
}

variable "resource_group_name" {
  description = "The track's management-sub resource group (D6)"
  type        = string
}

variable "location" {
  type = string
}

variable "workspace_id" {
  type = string
}

variable "action_group_ids" {
  description = "page and ticket (D11)"
  type        = object({ page = string, ticket = string })
}

variable "targets" {
  description = "What the rules watch: Odoo app names, the Postgres server name, the VPN gateway name, the Odoo database's id (Query Store)"
  type        = object({ apps = list(string), pg_server = string, gateway = string, database_id = optional(number, -1) })
}

variable "app_ids" {
  description = "Resource ids of the Odoo apps, for the restart metric alerts (M1, M2)"
  type        = map(string)
}

variable "pg_server_id" {
  description = "Resource id of the Postgres server, for M3 to M5"
  type        = string
}

variable "enabled" {
  description = "Whether the rules run: false on dev outside drills (docs/specs/round-1.md#routing)"
  type        = bool
}

variable "overrides" {
  description = "Per rule (a key of kql/rules.json, or M1 to M5): enabled, KQL parameters, a log rule's window and lookback, or a metric threshold, for drills"
  type = map(object({
    enabled   = optional(bool)
    params    = optional(map(string), {})
    threshold = optional(number)
    window    = optional(string) # a log rule's window and lookback, widened for a drill (Azure: at most P2D)
    lookback  = optional(string)
  }))
  default = {}
}

variable "tags" {
  type = map(string)
}
