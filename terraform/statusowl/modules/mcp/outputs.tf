output "function_arn" {
  description = "ARN of the MCP Lambda."
  value       = aws_lambda_function.mcp.arn
}

output "function_name" {
  description = "Name of the MCP Lambda."
  value       = aws_lambda_function.mcp.function_name
}

output "function_url" {
  description = "Function URL for the MCP Lambda. Callers must SigV4-sign requests (AuthType = AWS_IAM)."
  value       = aws_lambda_function_url.mcp.function_url
}

output "role_arn" {
  description = "ARN of the MCP Lambda's execution role."
  value       = aws_iam_role.mcp.arn
}
