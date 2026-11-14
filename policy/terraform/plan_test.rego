# Tests of plan.rego, on plans shaped like `terraform show -json` (format 1.2), never a real plan: a real one holds
# the password in clear.
package plan_test

import data.plan

rc(type, actions, after) := {"address": sprintf("%s.x", [type]), "mode": "managed", "type": type, "change": {"actions": actions, "after": after, "after_unknown": {}}}

tags := {"owner": "observability-track", "env": "stg"}

good := {"resource_changes": [
	rc("azurerm_resource_group", ["no-op"], {"name": "erp-stg-obs-rg", "tags": tags}),
	rc("azurerm_container_app_job", ["create"], {"resource_group_name": "erp-stg-obs-rg", "tags": tags}),
	rc("azurerm_monitor_scheduled_query_rules_alert_v2", ["update"], {"resource_group_name": "erp-mgmt-obs-rg", "tags": tags, "action": [{"action_groups": ["ag"]}]}),
	rc("azurerm_monitor_metric_alert", ["no-op"], {"resource_group_name": "erp-mgmt-obs-rg", "tags": tags, "action": [{"action_group_id": "ag"}]}),
	rc("azapi_resource", ["no-op"], {"type": "Microsoft.Insights/dataCollectionRules@2023-03-11", "tags": {"owner": "observability-track", "env": "shared"}}),
	rc("azapi_resource", ["no-op"], {"type": "Microsoft.OperationalInsights/workspaces/tables@2022-10-01", "tags": null}),
	rc("azurerm_role_assignment", ["no-op"], {"scope": "s"}),
	rc("random_password", ["no-op"], {"length": 32}),
]}

with_change(c) := {"resource_changes": array.concat(good.resource_changes, [c])}

test_good_passes if {
	count(plan.deny) == 0 with input as good
}

test_forbidden_type if {
	some msg in plan.deny with input as with_change(rc("azurerm_storage_account", ["create"], {"resource_group_name": "erp-stg-obs-rg", "tags": tags}))
	contains(msg, "not a type the track may create")
}

test_deleted_resource_not_checked if {
	count(plan.deny) == 0 with input as with_change(rc("azurerm_storage_account", ["delete"], null))
}

test_data_source_not_checked if {
	c := object.union(rc("azurerm_postgresql_flexible_server", ["read"], {"name": "x"}), {"mode": "data"})
	count(plan.deny) == 0 with input as with_change(c)
}

test_forbidden_arm_type if {
	some msg in plan.deny with input as with_change(rc("azapi_resource", ["create"], {"type": "Microsoft.Sql/servers@2023-01-01"}))
	contains(msg, "ARM type Microsoft.Sql/servers")
}

test_wrong_owner if {
	some msg in plan.deny with input as with_change(rc("azurerm_user_assigned_identity", ["create"], {"resource_group_name": "erp-stg-obs-rg", "tags": {"owner": "someone", "env": "stg"}}))
	contains(msg, "tag owner is not observability-track")
}

test_no_env_or_purpose if {
	some msg in plan.deny with input as with_change(rc("azurerm_user_assigned_identity", ["create"], {"resource_group_name": "erp-stg-obs-rg", "tags": {"owner": "observability-track"}}))
	contains(msg, "neither an env nor a purpose tag")
}

test_purpose_is_enough if {
	count(plan.deny) == 0 with input as with_change(rc("azurerm_user_assigned_identity", ["create"], {"resource_group_name": "erp-stg-obs-rg", "tags": {"owner": "observability-track", "purpose": "drill"}}))
}

test_platform_group if {
	some msg in plan.deny with input as with_change(rc("azurerm_container_app_job", ["create"], {"resource_group_name": "erp-stg-rg", "tags": tags}))
	contains(msg, "not one of the track's")
}

test_log_rule_without_group if {
	some msg in plan.deny with input as with_change(rc("azurerm_monitor_scheduled_query_rules_alert_v2", ["create"], {"resource_group_name": "erp-mgmt-obs-rg", "tags": tags, "action": [{"action_groups": []}]}))
	contains(msg, "no action group")
}

test_group_unknown_at_plan_time if {
	c := rc("azurerm_monitor_metric_alert", ["create"], {"resource_group_name": "erp-mgmt-obs-rg", "tags": tags})
	count(plan.deny) == 0 with input as with_change(object.union(c, {"change": {"after_unknown": {"action": true}}}))
}

test_repo_name if {
	some msg in plan.deny with input as with_change(rc("azurerm_monitor_action_group", ["update"], {"resource_group_name": "erp-mgmt-obs-rg", "tags": object.union(tags, {"repo": "someone/erp-observability"})}))
	contains(msg, "names the repo")
}
