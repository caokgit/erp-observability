# The ground rules on a saved plan (`terraform show -json`), in `obs.sh plan` before any apply: here the values are
# known, so the tags, the resource groups and the action groups are checked as they will reach Azure.
# Every managed resource the plan keeps or creates is checked, not only the changes, so a plan with no changes
# proves the live state complies too. A resource being deleted is not checked.
package plan

import data.lib

kept contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	rc.change.actions != ["delete"]
}

deny contains msg if {
	some rc in kept
	not lib.allowed_types[rc.type]
	msg := sprintf("%s: %s is not a type the track may create (only monitoring resources)", [rc.address, rc.type])
}

deny contains msg if {
	some rc in kept
	rc.type == "azapi_resource"
	not lib.allowed_arm_types[lib.arm_type(rc.change.after.type)]
	msg := sprintf("%s: ARM type %s is not one the track may create", [rc.address, rc.change.after.type])
}

taggable(rc) if lib.taggable_types[rc.type]

taggable(rc) if {
	rc.type == "azapi_resource"
	lib.taggable_arm_types[lib.arm_type(rc.change.after.type)]
}

deny contains msg if {
	some rc in kept
	taggable(rc)
	object.get(rc.change.after, ["tags", "owner"], "") != "observability-track"
	msg := sprintf("%s: tag owner is not observability-track", [rc.address])
}

deny contains msg if {
	some rc in kept
	taggable(rc)
	tags := object.get(rc.change.after, "tags", {})
	not tags.env
	not tags.purpose
	msg := sprintf("%s: neither an env nor a purpose tag", [rc.address])
}

# the track creates only in its own groups (erp-<env>-obs-rg, erp-mgmt-obs-rg), never in a platform group;
# the custom tables are the one exception: they live in the platform's workspace (azapi, parent_id)
deny contains msg if {
	some rc in kept
	rg := object.get(rc.change.after, "resource_group_name", object.get(rc.change.after, "name", ""))
	rc.type != "azapi_resource"
	has_group(rc)
	not contains(rg, "-obs-")
	msg := sprintf("%s: in resource group %s, not one of the track's (-obs-)", [rc.address, rg])
}

has_group(rc) if rc.change.after.resource_group_name
has_group(rc) if rc.type == "azurerm_resource_group"

deny contains msg if {
	some rc in kept
	rc.type == "azurerm_monitor_scheduled_query_rules_alert_v2"
	not log_rule_has_group(rc)
	msg := sprintf("%s: no action group (an alert nobody receives)", [rc.address])
}

deny contains msg if {
	some rc in kept
	rc.type == "azurerm_monitor_metric_alert"
	not metric_rule_has_group(rc)
	msg := sprintf("%s: no action group (an alert nobody receives)", [rc.address])
}

deny contains msg if {
	some rc in kept
	some path, value
	walk(rc.change.after, [path, value])
	is_string(value)
	regex.match(lib.repo_names, value)
	msg := sprintf("%s: a value names the repo (%s)", [rc.address, regex.find_n(lib.repo_names, value, 1)[0]])
}

log_rule_has_group(rc) if {
	some a in rc.change.after.action
	count(a.action_groups) > 0
}

# an action group created in the same apply is not known yet at plan time
log_rule_has_group(rc) if rc.change.after_unknown.action

metric_rule_has_group(rc) if {
	some a in rc.change.after.action
	a.action_group_id
}

metric_rule_has_group(rc) if rc.change.after_unknown.action
