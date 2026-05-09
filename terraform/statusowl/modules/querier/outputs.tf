output "function_arn" {
  description = "ARN of the querier Lambda."
  value       = aws_lambda_function.querier.arn
}

output "function_name" {
  description = "Name of the querier Lambda."
  value       = aws_lambda_function.querier.function_name
}

output "role_arn" {
  description = "ARN of the querier's execution role."
  value       = aws_iam_role.querier.arn
}

output "bucket_name" {
  description = "Name of the shared statusowl bucket (querier writes audit/, MCP will use cache/)."
  value       = aws_s3_bucket.shared.bucket
}

output "bucket_arn" {
  description = "ARN of the shared statusowl bucket. Exposed for the future MCP module to scope its IAM to cache/* prefixes."
  value       = aws_s3_bucket.shared.arn
}
