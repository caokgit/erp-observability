# The landing zone's service control policies (docs/specs/aws-migration.md#guardrails-the-scps): five preventive
# guardrails, each attached to the organizational units named in var.attachments. Designed, tested with a mock
# provider, never applied (docs/specs/aws-migration.md#acceptance).

locals {
  # Global services answer from us-east-1 whatever the caller's region, so the region guardrail leaves them out.
  global_actions = [
    "iam:*", "organizations:*", "sts:*", "support:*", "account:*", "budgets:*", "ce:*", "cur:*",
    "health:*", "route53:*", "route53domains:*", "cloudfront:*", "waf:*", "wafv2:*", "shield:*",
    "globalaccelerator:*", "sso:*", "identitystore:*", "trustedadvisor:*", "pricing:*",
  ]

  # Who may still change the guardrails' own services: the landing zone's administration roles.
  admin_role_patterns = [for r in var.admin_roles : "arn:aws:iam::*:role/${r}"]

  policies = {
    "deny-outside-regions" = {
      description = "Deny every regional action outside the allowed regions"
      document = {
        Version = "2012-10-17"
        Statement = [{
          Sid       = "DenyOutsideRegions"
          Effect    = "Deny"
          NotAction = local.global_actions
          Resource  = "*"
          Condition = {
            StringNotEquals = { "aws:RequestedRegion" = var.allowed_regions }
            ArnNotLike      = { "aws:PrincipalArn" = local.admin_role_patterns }
          }
        }]
      }
    }
    "protect-security-services" = {
      description = "Deny stopping or deleting CloudTrail, Config, GuardDuty and Security Hub"
      document = {
        Version = "2012-10-17"
        Statement = [{
          Sid    = "ProtectSecurityServices"
          Effect = "Deny"
          Action = [
            "cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:UpdateTrail", "cloudtrail:PutEventSelectors",
            "config:StopConfigurationRecorder", "config:DeleteConfigurationRecorder", "config:DeleteDeliveryChannel",
            "guardduty:DeleteDetector", "guardduty:DisassociateFromMasterAccount", "guardduty:DisassociateFromAdministratorAccount",
            "guardduty:UpdateDetector", "securityhub:DisableSecurityHub", "securityhub:DisassociateFromMasterAccount",
            "securityhub:DisassociateFromAdministratorAccount",
          ]
          Resource  = "*"
          Condition = { ArnNotLike = { "aws:PrincipalArn" = local.admin_role_patterns } }
        }]
      }
    }
    "deny-leave-organization" = {
      description = "Deny an account leaving the organization"
      document = {
        Version   = "2012-10-17"
        Statement = [{ Sid = "DenyLeaveOrganization", Effect = "Deny", Action = ["organizations:LeaveOrganization"], Resource = "*" }]
      }
    }
    "deny-root-user" = {
      description = "Deny every action by an account's root user"
      document = {
        Version = "2012-10-17"
        Statement = [{
          Sid       = "DenyRootUser"
          Effect    = "Deny"
          Action    = ["*"]
          Resource  = "*"
          Condition = { StringLike = { "aws:PrincipalArn" = ["arn:aws:iam::*:root"] } }
        }]
      }
    }
    "require-tags" = {
      description = "Deny creating the main billable resources without the cost allocation tags"
      document = {
        Version = "2012-10-17"
        Statement = [for tag in var.required_tags : {
          Sid       = "RequireTag${replace(title(tag), "-", "")}"
          Effect    = "Deny"
          Action    = var.tagged_create_actions
          Resource  = "*"
          Condition = { Null = { "aws:RequestTag/${tag}" = "true" } }
        }]
      }
    }
  }

  # One attachment per (policy, target) pair named in var.attachments.
  attachments = merge([
    for policy, targets in var.attachments : { for t in targets : "${policy}/${t}" => { policy = policy, target = t } }
  ]...)
}

resource "aws_organizations_policy" "this" {
  for_each    = local.policies
  name        = each.key
  description = each.value.description
  type        = "SERVICE_CONTROL_POLICY"
  content     = jsonencode(each.value.document)
  tags        = var.tags
}

resource "aws_organizations_policy_attachment" "this" {
  for_each  = local.attachments
  policy_id = aws_organizations_policy.this[each.value.policy].id
  target_id = each.value.target
}
