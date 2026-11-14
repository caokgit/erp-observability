# Names come from terraform/names.sh (names.auto.tfvars.json); the alert routes from routes.auto.tfvars.json, written
# from the owner's notes. Both committed, the repo being private (AGENTS.md#writing).

variable "subscription_ids" {
  description = "Subscription ids by role: management, dev, stg, prd, connectivity"
  type        = map(string)
}

variable "alert_routes" {
  description = "Per environment: the Teams workflow URL of its channel, and the account that owns the flow (D11)"
  type        = map(object({ teams_webhook = string, flows_owner = string }))
  sensitive   = true
}

# Written by terraform/names.sh for every root; not used here
variable "quiet_resolves" {
  description = "Environments whose Logic App posts no card when a ticket (Sev3) resolves (round 6, item 4)"
  type        = set(string)
  default     = ["dev", "stg"]
}

variable "workspace_customer_id" {
  type    = string
  default = ""
}
variable "gateway" {
  type    = any
  default = null
}
variable "registry" {
  type    = any
  default = null
}
variable "state" {
  type    = any
  default = null
}
