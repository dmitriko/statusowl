module "querier" {
  source = "./modules/querier"

  name_prefix            = var.name_prefix
  spoke_account_roles    = var.spoke_account_roles
  audit_retention_days   = var.audit_retention_days
  lambda_memory_mb       = var.lambda_memory_mb
  lambda_timeout_seconds = var.lambda_timeout_seconds
  function_zip_url       = var.function_zip_url
  function_zip_sha256    = var.function_zip_sha256
  function_zip_path      = var.function_zip_path
  function_source_dir    = var.function_source_dir
  log_retention_days     = var.log_retention_days
  tags                   = var.tags
}
