output "querier_function_arn" {
  description = "ARN of the querier Lambda."
  value       = module.querier.function_arn
}

output "querier_function_name" {
  description = "Name of the querier Lambda."
  value       = module.querier.function_name
}

output "querier_role_arn" {
  description = "ARN of the querier's execution role. Trust this principal in spoke-account read-only role trust policies."
  value       = module.querier.role_arn
}

output "audit_bucket_name" {
  description = "Name of the S3 bucket holding querier audit records."
  value       = module.querier.audit_bucket_name
}
