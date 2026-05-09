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

output "mcp_function_url" {
  description = "Function URL of the MCP Lambda (null when enable_mcp = false). Callers must SigV4-sign requests."
  value       = var.enable_mcp ? module.mcp[0].function_url : null
}

output "mcp_function_arn" {
  description = "ARN of the MCP Lambda (null when enable_mcp = false)."
  value       = var.enable_mcp ? module.mcp[0].function_arn : null
}

output "mcp_role_arn" {
  description = "ARN of the MCP Lambda's execution role (null when enable_mcp = false)."
  value       = var.enable_mcp ? module.mcp[0].role_arn : null
}
