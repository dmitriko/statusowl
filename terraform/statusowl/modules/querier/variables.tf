variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 24
    error_message = "name_prefix must be 1-24 chars."
  }
}

variable "spoke_account_roles" {
  description = "Map of account name => role ARN the querier may assume cross-account."
  type        = map(string)
  default     = {}
}

variable "audit_retention_days" {
  description = "Days to retain audit log objects in S3."
  type        = number
  default     = 90
}

variable "lambda_memory_mb" {
  description = "Memory size (MB) for the querier Lambda."
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Hard Lambda timeout (seconds)."
  type        = number
  default     = 90
}

variable "function_zip_url" {
  description = "URL to fetch the Lambda zip from. Verified against function_zip_sha256 if set."
  type        = string
  default     = null
}

variable "function_zip_sha256" {
  description = "Hex-encoded SHA-256 expected for the zip downloaded from function_zip_url."
  type        = string
  default     = null
  validation {
    condition     = var.function_zip_sha256 == null || can(regex("^[0-9a-fA-F]{64}$", var.function_zip_sha256))
    error_message = "function_zip_sha256 must be a 64-char hex SHA-256."
  }
}

variable "function_zip_path" {
  description = "Local path to a pre-built Lambda zip (highest precedence)."
  type        = string
  default     = null
}

variable "function_source_dir" {
  description = "Source dir to zip when no zip path/URL is given. Null = default in-repo path."
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
