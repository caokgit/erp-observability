variable "allowed_regions" {
  description = "Regions where regional actions are allowed (the design: ap-southeast-1, and us-east-1 for global endpoints)"
  type        = list(string)
  default     = ["ap-southeast-1", "us-east-1"]

  validation {
    condition     = length(var.allowed_regions) > 0 && alltrue([for r in var.allowed_regions : can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", r))])
    error_message = "allowed_regions must hold at least one region code such as ap-southeast-1."
  }
}

variable "admin_roles" {
  description = "IAM role names (without path) that the region and security-service guardrails exempt"
  type        = list(string)
  default     = ["AWSControlTowerExecution", "landing-zone-admin"]
}

variable "required_tags" {
  description = "Tag keys a create action must carry (the showback keys)"
  type        = list(string)
  default     = ["env", "app", "cost-center"]

  validation {
    condition     = length(var.required_tags) > 0
    error_message = "required_tags must name at least one tag key."
  }
}

variable "tagged_create_actions" {
  description = "Create actions the require-tags guardrail checks"
  type        = list(string)
  default = [
    "ec2:RunInstances", "rds:CreateDBInstance", "rds:CreateDBCluster", "ecs:CreateService", "ecs:CreateCluster",
    "elasticloadbalancing:CreateLoadBalancer", "s3:CreateBucket", "elasticfilesystem:CreateFileSystem",
  ]
}

variable "attachments" {
  description = "Policy name to the organization root, OU or account ids it is attached to"
  type        = map(list(string))

  validation {
    condition = alltrue([for p in keys(var.attachments) : contains(
    ["deny-outside-regions", "protect-security-services", "deny-leave-organization", "deny-root-user", "require-tags"], p)])
    error_message = "attachments may name only the module's five policies."
  }
}

variable "tags" {
  description = "Tags on the policies themselves"
  type        = map(string)
  default     = {}
}
