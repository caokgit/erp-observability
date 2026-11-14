# The AWS design: rerun its numbers and tests

How to rerun the two things behind the [Azure to AWS design](../specs/aws-migration.md): the cost estimate from both
public price lists, and the guardrails' tests on a mock provider. Neither needs an AWS or Azure login, and neither
creates anything ([D20](../design.md#decisions)). Map of the runbooks: [README](README.md).

## Prerequisites

| Need | Check |
|---|---|
| Python 3.11+ and network access to `pricing.us-east-1.amazonaws.com` and `prices.azure.com` | `python3 --version` |
| Terraform 1.7 or newer (`mock_provider`) and the AWS provider | The lab's toolchain: `$HOME/lab/.toolchain/bin/terraform version` |

## Rerun the cost estimate

```bash
python3 terraform/aws/cost/estimate.py --cache .scratch_tf/pricing > .scratch_tf/estimate.md
grep '^## ' .scratch_tf/estimate.md
```

The first run downloads about 25 MB of price files into the gitignored cache (the RDS file is 23.8 MB; the EC2 file,
350 MB, is not read: the NAT gateway's price is a constant with its source version in the script). Output of
2026-11-08 (REAL, trimmed):

```text
## Unit prices (read 2026-11-08)
## Azure today, list prices, apps at the active rate (upper bound): USD 1,064.39 a month
## Azure today, list prices, apps at the idle rate (lower bound): USD 611.06 a month
## AWS design, the live database Multi-AZ: USD 1,280.24 a month
## AWS design, every database Single-AZ (like for like): USD 1,091.76 a month
## Database options for the live database (USD a month, 730 h, compute only)
```

Check: every unit price row names a Price List version or the Retail Prices API; the totals match the
[spec's cost](../specs/aws-migration.md#cost), or the spec is updated with the new numbers and their date.

- If you see `no price for ...`: AWS renamed a usage type or description in a new price file; find the new one with the
  offer's JSON and update the matcher in the script.
- A price file changed version since the last run: the cache keeps the old file under its version name; the script
  reads the current index each run, so delete nothing.

## Test the guardrails

```bash
cat > .scratch_tf/aws.tfrc <<'EOF'
provider_installation {
  filesystem_mirror {
    path    = "/home/<user>/lab/.scratch_tf/plugins"
    include = ["registry.terraform.io/hashicorp/aws"]
  }
  direct {
    exclude = ["registry.terraform.io/hashicorp/aws"]
  }
}
EOF
export PATH=$HOME/lab/.toolchain/bin:$PATH
export TF_CLI_CONFIG_FILE=$PWD/.scratch_tf/aws.tfrc TF_DATA_DIR=$PWD/.scratch_tf/aws-scp
cd terraform/aws/modules/scp
terraform fmt -check -recursive && terraform init -backend=false -input=false && terraform validate && terraform test
rm -f .terraform.lock.hcl   # a module carries no lock file
```

The mirror reuses the AWS provider the lab already downloaded (6.71.0), read only; without it, drop `TF_CLI_CONFIG_FILE`
and Terraform downloads the provider. Output of 2026-11-08 (REAL, trimmed):

```text
Success! The configuration is valid.
  run "five_policies_all_scps"... pass
  run "region_guardrail_allows_only_the_listed_regions"... pass
  run "security_services_and_root_are_protected"... pass
  run "one_require_tag_statement_per_key"... pass
  run "rejects_an_unknown_policy_name"... pass
  run "rejects_a_bad_region"... pass
Success! 6 passed, 0 failed.
```

Check: `6 passed, 0 failed`. No AWS credential is read: `mock_provider "aws"` answers every call.

- If a count assertion fails after a change to `attachments` in the test: recount the (policy, target) pairs; on
  2026-11-08 the test itself expected 9 for 8 pairs and was the one corrected.

## Rollback

Nothing to roll back: both steps write only to `.scratch_tf/` (gitignored). Delete it to clean up.
