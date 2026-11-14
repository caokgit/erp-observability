output "policy_ids" {
  description = "Policy name to its id"
  value       = { for k, p in aws_organizations_policy.this : k => p.id }
}

output "attachment_count" {
  description = "How many (policy, target) attachments the module made"
  value       = length(aws_organizations_policy_attachment.this)
}
