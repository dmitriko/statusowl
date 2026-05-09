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

variable "function_zip_path" {
  description = <<-EOT
    Path to a pre-built Lambda deployment zip. Recommended for CI: build the
    zip in your pipeline, set this to its path. If null, the module builds a
    zip from `function_source_dir` via the archive_file data source — fine
    for local dev, not great for reproducible CI.
  EOT
  type        = string
  default     = null
}

variable "function_source_dir" {
  description = <<-EOT
    Source directory to zip when `function_zip_path` is null. Defaults inside
    the sub-module to the in-repo cmd/querier/src layout; override if you've
    vendored or relocated the source tree.
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
