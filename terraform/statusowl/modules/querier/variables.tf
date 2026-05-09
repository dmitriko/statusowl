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

variable "function_zip_path" {
  description = "Path to a pre-built Lambda deployment zip. Null = build via archive_file."
  type        = string
  default     = null
}

variable "function_source_dir" {
  description = "Source dir to zip when function_zip_path is null. Null = default in-repo path."
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
