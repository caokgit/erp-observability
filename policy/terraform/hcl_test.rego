# Tests of hcl.rego: each rule with a compliant input and one that breaks it (conftest verify, opa test).
package hcl_test

import data.hcl

good := {"resource": {
	"azurerm_monitor_scheduled_query_rules_alert_v2": {"log": [{
		"tags": "${var.tags}",
		"action": [{"action_groups": ["${var.action_group_ids[each.value.group]}"]}],
	}]},
	"azurerm_monitor_metric_alert": {"metric": [{
		"tags": "${var.tags}",
		"action": [{"action_group_id": "${var.action_group_ids[each.value.group]}"}],
	}]},
	"azapi_resource": {
		"dcr": [{"type": "Microsoft.Insights/dataCollectionRules@2023-03-11", "tags": "${local.tags}"}],
		"table": [{"type": "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"}],
	},
	"azurerm_role_assignment": {"pull": [{"role_definition_name": "Container Registry Repository Reader"}]},
}}

test_good_passes if {
	count(hcl.deny) == 0 with input as good
}

test_forbidden_type if {
	bad := object.union(good, {"resource": {"azurerm_postgresql_flexible_server": {"x": [{"tags": "${var.tags}"}]}}})
	some msg in hcl.deny with input as bad
	contains(msg, "not a type the track may create")
}

test_forbidden_arm_type if {
	bad := {"resource": {"azapi_resource": {"vnet": [{"type": "Microsoft.Network/virtualNetworks@2024-01-01", "tags": "x"}]}}}
	some msg in hcl.deny with input as bad
	contains(msg, "ARM type Microsoft.Network/virtualNetworks")
}

test_missing_tags if {
	bad := {"resource": {"azurerm_user_assigned_identity": {"job": [{"name": "x"}]}}}
	some msg in hcl.deny with input as bad
	contains(msg, "sets no tags")
}

test_untaggable_needs_no_tags if {
	count(hcl.deny) == 0 with input as {"resource": {"azurerm_role_assignment": {"r": [{"scope": "x"}]}}}
}

test_log_rule_without_group if {
	bad := {"resource": {"azurerm_monitor_scheduled_query_rules_alert_v2": {"log": [{"tags": "x", "action": [{"action_groups": []}]}]}}}
	some msg in hcl.deny with input as bad
	contains(msg, "no action group")
}

test_metric_rule_without_group if {
	bad := {"resource": {"azurerm_monitor_metric_alert": {"metric": [{"tags": "x"}]}}}
	some msg in hcl.deny with input as bad
	contains(msg, "no action group")
}

test_repo_name if {
	bad := {"resource": {"azurerm_resource_group": {"rg": [{"tags": {"repo": "someone/erp-observability"}}]}}}
	some msg in hcl.deny with input as bad
	contains(msg, "names the repo")
}
