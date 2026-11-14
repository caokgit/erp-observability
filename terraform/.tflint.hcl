# tflint for the track's Terraform (docs/specs/pipeline.md#the-workflow): the terraform ruleset's recommended preset,
# with two rules off for reasons of this repo's layout. Run by tools/ci.sh (tflint --recursive --chdir=terraform).

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Each root declares every name terraform/names.sh writes into its names.auto.tfvars.json, used here or not: some are
# read only by kql/backtest.py, and an undeclared value in an *.auto.tfvars file makes Terraform warn on every plan.
rule "terraform_unused_declarations" {
  enabled = false
}

# The modules are called only by the three roots, which pin required_version; a module has no lock file of its own.
rule "terraform_required_version" {
  enabled = false
}
