# The SCP module on a mock provider: no AWS account, no credentials (docs/specs/aws-migration.md#acceptance, M7).
# Run: terraform -chdir=terraform/aws/modules/scp init -backend=false && terraform -chdir=terraform/aws/modules/scp test

mock_provider "aws" {}

variables {
  # TOY ids in the organizations' format; the design's OUs: docs/specs/aws-migration.md#the-organization
  attachments = {
    "deny-outside-regions"      = ["ou-toy0-workload", "ou-toy0-infra"]
    "protect-security-services" = ["r-toy0"]
    "deny-leave-organization"   = ["r-toy0"]
    "deny-root-user"            = ["ou-toy0-workload", "ou-toy0-infra", "ou-toy0-security"]
    "require-tags"              = ["ou-toy0-workload"]
  }
}

run "five_policies_all_scps" {
  command = plan

  assert {
    condition     = length(aws_organizations_policy.this) == 5
    error_message = "expected the five guardrails"
  }
  assert {
    condition     = alltrue([for p in aws_organizations_policy.this : p.type == "SERVICE_CONTROL_POLICY"])
    error_message = "every policy must be a service control policy"
  }
  assert {
    condition     = length(aws_organizations_policy_attachment.this) == 8
    error_message = "expected one attachment per (policy, target) pair: 2 + 1 + 1 + 3 + 1"
  }
}

run "region_guardrail_allows_only_the_listed_regions" {
  command = plan

  assert {
    condition     = jsondecode(aws_organizations_policy.this["deny-outside-regions"].content).Statement[0].Condition.StringNotEquals["aws:RequestedRegion"] == ["ap-southeast-1", "us-east-1"]
    error_message = "the region guardrail must deny everything outside ap-southeast-1 and us-east-1"
  }
  assert {
    condition     = contains(jsondecode(aws_organizations_policy.this["deny-outside-regions"].content).Statement[0].NotAction, "iam:*")
    error_message = "global services (IAM) must stay outside the region guardrail"
  }
}

run "security_services_and_root_are_protected" {
  command = plan

  assert {
    condition     = contains(jsondecode(aws_organizations_policy.this["protect-security-services"].content).Statement[0].Action, "cloudtrail:StopLogging")
    error_message = "stopping the organization trail must be denied"
  }
  assert {
    condition     = contains(jsondecode(aws_organizations_policy.this["protect-security-services"].content).Statement[0].Action, "guardduty:DeleteDetector")
    error_message = "deleting GuardDuty must be denied"
  }
  assert {
    condition     = jsondecode(aws_organizations_policy.this["deny-root-user"].content).Statement[0].Condition.StringLike["aws:PrincipalArn"] == ["arn:aws:iam::*:root"]
    error_message = "the root user guardrail must match every account's root"
  }
}

run "one_require_tag_statement_per_key" {
  command = plan

  variables {
    required_tags = ["env", "app"]
  }

  assert {
    condition     = length(jsondecode(aws_organizations_policy.this["require-tags"].content).Statement) == 2
    error_message = "expected one statement per required tag"
  }
  assert {
    condition     = jsondecode(aws_organizations_policy.this["require-tags"].content).Statement[0].Condition.Null["aws:RequestTag/env"] == "true"
    error_message = "a create without the env tag must be denied"
  }
}

run "rejects_an_unknown_policy_name" {
  command = plan

  variables {
    attachments = { "allow-everything" = ["r-toy0"] }
  }

  expect_failures = [var.attachments]
}

run "rejects_a_bad_region" {
  command = plan

  variables {
    allowed_regions = ["singapore"]
  }

  expect_failures = [var.allowed_regions]
}
