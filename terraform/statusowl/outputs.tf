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

output "bucket_name" {
  description = "Name of the shared statusowl bucket (querier writes audit/, MCP will use cache/)."
  value       = module.querier.bucket_name
}

output "bucket_arn" {
  description = "ARN of the shared statusowl bucket."
  value       = module.querier.bucket_arn
}
