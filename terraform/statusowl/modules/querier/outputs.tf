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

output "audit_bucket_name" {
  description = "Name of the audit S3 bucket."
  value       = aws_s3_bucket.audit.bucket
}
