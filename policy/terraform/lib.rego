# The track's ground rules as data, shared by the HCL and the plan policies (docs/specs/pipeline.md#the-policies).
# A new resource type joins a list here in the same commit that first creates it, with its reason in the spec.
package lib

# "Terraform creates monitoring resources only" (AGENTS.md): every managed type the roots create, 2026-11-08
allowed_types := {
	"azurerm_resource_group", # the track's own groups (erp-<env>-obs-rg)
	"azurerm_user_assigned_identity", # the SQL job's identity
	"azurerm_role_assignment", # the identity's ingestion and pull roles
	"azurerm_container_app_job", # the SQL job and the log reader
	"azurerm_monitor_action_group",
	"azurerm_monitor_metric_alert",
	"azurerm_monitor_scheduled_query_rules_alert_v2",
	"azurerm_logic_app_workflow", # the card's Logic App per environment
	"azurerm_logic_app_trigger_http_request",
	"azurerm_logic_app_action_custom",
	"random_password", # obs_monitor's password (never leaves the state)
	"azapi_resource", # only the ARM types below
}

# azapi_resource reaches any ARM type, so its type is listed too (without the API version)
allowed_arm_types := {
	"Microsoft.OperationalInsights/workspaces/tables", # the custom tables in the platform's workspace
	"Microsoft.Insights/dataCollectionRules", # the DCR, the gate into those tables
}

# types that hold tags; the others (role assignments, Logic App steps, passwords, tables) have none
taggable_types := {
	"azurerm_resource_group",
	"azurerm_user_assigned_identity",
	"azurerm_container_app_job",
	"azurerm_monitor_action_group",
	"azurerm_monitor_metric_alert",
	"azurerm_monitor_scheduled_query_rules_alert_v2",
	"azurerm_logic_app_workflow",
}

taggable_arm_types := {"Microsoft.Insights/dataCollectionRules"}

# "Nothing in Azure names the GitHub repo" (AGENTS.md): the account and the repos' names. The paths inside the repo
# are left to tools/no-repo-trace.py, since the HCL names its own files (file(), path.module) and they stay local.
repo_names := `(?i)caokgit|erp-observability|ocr-platform|github`

arm_type(t) := split(t, "@")[0]
