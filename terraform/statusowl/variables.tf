variable "name_prefix" {
  description = "Prefix for resource names. Lets multiple statusowl deployments coexist in one account."
  type        = string
  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 24
    error_message = "name_prefix must be 1-24 chars (Lambda function names are capped at 64; we leave room for suffixes)."
  }
}

variable "spoke_account_roles" {
  description = <<-EOT
    Cross-account read-only roles the querier may assume, keyed by the
    account name the model uses in run_python events. Empty = single-account
    install. Example:
      {
        prod = "arn:aws:iam::111111111111:role/statusowl-readonly"
        dev  = "arn:aws:iam::222222222222:role/statusowl-readonly"
      }
  EOT
  type        = map(string)
  default     = {}
}

variable "audit_retention_days" {
  description = "Days to retain audit log objects in S3 before lifecycle deletion."
  type        = number
  default     = 90
}

variable "lambda_memory_mb" {
  description = "Memory size (MB) for the querier Lambda."
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Hard Lambda timeout (seconds). The handler enforces a softer per-invocation timeout from the event."
  type        = number
  default     = 90
}

variable "function_zip_url" {
  description = <<-EOT
    URL to fetch the Lambda zip from. Recommended for production: pin to a
    versioned `querier-v*` GitHub release asset. The module fetches at plan
    time and verifies the SHA-256 if `function_zip_sha256` is set.
    Ignored when `function_zip_path` is also set.
  EOT
  type        = string
  default     = null
}

variable "function_zip_sha256" {
  description = <<-EOT
    Hex-encoded SHA-256 of the zip fetched via `function_zip_url`. Strongly
    recommended for production: the module refuses to deploy on mismatch.
    No effect when `function_zip_url` is null.
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
    `function_zip_url` and the built-in source build. Useful for CI that
    builds the zip in-pipeline, or for air-gapped/mirror setups.
  EOT
  type        = string
  default     = null
}

variable "function_source_dir" {
  description = <<-EOT
    Source directory the module zips when neither `function_zip_path` nor
    `function_zip_url` is set. Defaults to the in-repo `cmd/querier/src`
    layout; override if you've vendored or relocated the source tree.
  EOT
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the querier Lambda."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

# --- MCP sub-module ---

variable "enable_mcp" {
  description = "Whether to deploy the MCP server Lambda + Function URL."
  type        = bool
  default     = true
}

variable "mcp_lambda_memory_mb" {
  description = "Memory size (MB) for the MCP Lambda."
  type        = number
  default     = 256
}

variable "mcp_lambda_timeout_seconds" {
  description = "Hard Lambda timeout (seconds) for the MCP Lambda."
  type        = number
  default     = 120
}

variable "mcp_lambda_architecture" {
  description = "CPU architecture for the MCP Lambda. arm64 (Graviton) is cheaper for the same throughput."
  type        = string
  default     = "arm64"
}

variable "mcp_function_zip_url" {
  description = "Release URL for the MCP Lambda zip (statusowl-mcp_lambda_<arch>.zip). See README §Choosing a Lambda artifact source."
  type        = string
  default     = null
}

variable "mcp_function_zip_sha256" {
  description = "Hex SHA-256 of the MCP Lambda zip fetched via mcp_function_zip_url."
  type        = string
  default     = null
}

variable "mcp_function_zip_path" {
  description = "Local path to a pre-built MCP Lambda zip. Highest precedence."
  type        = string
  default     = null
}

variable "mcp_log_retention_days" {
  description = "CloudWatch Logs retention for the MCP Lambda."
  type        = number
  default     = 30
}
