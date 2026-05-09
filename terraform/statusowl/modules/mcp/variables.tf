variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "querier_function_arn" {
  description = "ARN of the deployed querier Lambda. The MCP role gets lambda:InvokeFunction on this ARN — and nothing else."
  type        = string
}

variable "querier_function_name" {
  description = "Name of the querier Lambda. Set on the MCP Lambda as STATUSOWL_QUERIER_FUNCTION_NAME."
  type        = string
}

variable "lambda_memory_mb" {
  description = "Memory size (MB) for the MCP Lambda."
  type        = number
  default     = 256
}

variable "lambda_timeout_seconds" {
  description = "Hard Lambda timeout (seconds). Should comfortably exceed the querier's max."
  type        = number
  default     = 120
}

variable "lambda_architecture" {
  description = "CPU architecture for the MCP Lambda. arm64 (Graviton) is cheaper for the same throughput; flip to x86_64 only if you have a specific reason."
  type        = string
  default     = "arm64"
  validation {
    condition     = contains(["arm64", "x86_64"], var.lambda_architecture)
    error_message = "lambda_architecture must be one of: arm64, x86_64."
  }
}

variable "function_zip_url" {
  description = <<-EOT
    URL to fetch the Lambda zip from. Recommended for production: pin to a
    versioned `mcp-v*` GitHub release asset (statusowl-mcp_lambda_<arch>.zip).
    Verified against `function_zip_sha256` if set.
    Ignored when `function_zip_path` is also set.
  EOT
  type        = string
  default     = null
}

variable "function_zip_sha256" {
  description = <<-EOT
    Hex-encoded SHA-256 of the zip fetched via `function_zip_url`. Strongly
    recommended for production: the module refuses to deploy on mismatch.
  EOT
  type        = string
  default     = null
  validation {
    condition     = var.function_zip_sha256 == null || can(regex("^[0-9a-fA-F]{64}$", var.function_zip_sha256))
    error_message = "function_zip_sha256 must be a 64-char hex SHA-256."
  }
}

variable "function_zip_path" {
  description = <<-EOT
    Local path to a pre-built Lambda zip. Highest precedence — overrides
    `function_zip_url` and the built-in build fallback.
  EOT
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the MCP Lambda."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
