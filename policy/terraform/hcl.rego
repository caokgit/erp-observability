# The ground rules on the Terraform source, one .tf file at a time (conftest's hcl2 parser), in CI on every push.
# Values set from variables are unknown here, so the tags rule asks only that a taggable resource sets tags; the
# values are checked on the plan (plan.rego).
package hcl

import data.lib

deny contains msg if {
	some type, name
	input.resource[type][name]
	not lib.allowed_types[type]
	msg := sprintf("%s.%s: %s is not a type the track may create (only monitoring resources)", [type, name, type])
}

deny contains msg if {
	some name, block in input.resource.azapi_resource
	some b in block
	not lib.allowed_arm_types[lib.arm_type(b.type)]
	msg := sprintf("azapi_resource.%s: ARM type %s is not one the track may create", [name, b.type])
}

deny contains msg if {
	some type, name
	some b in input.resource[type][name]
	lib.taggable_types[type]
	not b.tags
	msg := sprintf("%s.%s: sets no tags (owner = observability-track is required)", [type, name])
}

deny contains msg if {
	some name, block in input.resource.azapi_resource
	some b in block
	lib.taggable_arm_types[lib.arm_type(b.type)]
	not b.tags
	msg := sprintf("azapi_resource.%s: sets no tags (owner = observability-track is required)", [name])
}

deny contains msg if {
	some name, block in input.resource.azurerm_monitor_scheduled_query_rules_alert_v2
	some b in block
	not log_rule_has_group(b)
	msg := sprintf("azurerm_monitor_scheduled_query_rules_alert_v2.%s: no action group (an alert nobody receives)", [name])
}

deny contains msg if {
	some name, block in input.resource.azurerm_monitor_metric_alert
	some b in block
	not metric_rule_has_group(b)
	msg := sprintf("azurerm_monitor_metric_alert.%s: no action group (an alert nobody receives)", [name])
}

deny contains msg if {
	some path, value
	walk(input, [path, value])
	is_string(value)
	regex.match(lib.repo_names, value)
	msg := sprintf("%s: names the repo (%s)", [concat(".", [sprintf("%v", [p]) | some p in path]), regex.find_n(lib.repo_names, value, 1)[0]])
}

log_rule_has_group(b) if {
	some a in b.action
	count(a.action_groups) > 0
}

metric_rule_has_group(b) if {
	some a in b.action
	a.action_group_id
}
