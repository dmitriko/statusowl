data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  function_name = "${var.name_prefix}-querier"

  # Source selection. Precedence: explicit path > URL fetch > archive_file build.
  use_zip_path = var.function_zip_path != null
  use_zip_url  = !local.use_zip_path && var.function_zip_url != null
  use_archive  = !local.use_zip_path && !local.use_zip_url

  # Default in-repo source dir, used only by the archive_file path.
  default_source_dir = "${path.module}/../../../../cmd/querier/src"
  source_dir         = coalesce(var.function_source_dir, local.default_source_dir)

  # Conditional expressions short-circuit, so each branch's references are
  # only evaluated when its mode is active.
  zip_path = (
    local.use_zip_path ? var.function_zip_path :
    local.use_zip_url ? data.external.fetch_zip[0].result.path :
    data.archive_file.querier[0].output_path
  )
  zip_hash = (
    local.use_zip_path ? filebase64sha256(var.function_zip_path) :
    local.use_zip_url ? data.external.fetch_zip[0].result.sha256_b64 :
    data.archive_file.querier[0].output_base64sha256
  )
}

# --- Source A: archive_file builds from local source (development default) ---

data "archive_file" "querier" {
  count = local.use_archive ? 1 : 0

  type        = "zip"
  source_dir  = local.source_dir
  output_path = "${path.module}/.build/querier.zip"

  excludes = [
    "**/__pycache__",
    "**/__pycache__/**",
    "**/*.pyc",
    "**/.pytest_cache",
    "**/.pytest_cache/**",
  ]

  lifecycle {
    precondition {
      condition     = fileexists("${local.source_dir}/querier/handler.py")
      error_message = <<-EOT
        Cannot find querier source at ${local.source_dir}/querier/handler.py.

        Resolved source_dir: ${local.source_dir}

        Fix one of:
          - set `function_zip_url` to a published release asset
          - set `function_zip_path` to a pre-built zip from your CI
          - set `function_source_dir` to the directory that contains the
            `querier/` package
      EOT
    }
  }
}

# --- Source B: external script fetches from URL and verifies SHA-256 ---
#
# Runs at plan time. On SHA-256 mismatch the script exits non-zero and
# Terraform reports a plan error — a tampered or wrong-version artifact
# never makes it into source_code_hash.

data "external" "fetch_zip" {
  count = local.use_zip_url ? 1 : 0

  program = ["python3", "${path.module}/scripts/fetch-zip.py"]

  query = {
    url          = var.function_zip_url
    expected_sha = var.function_zip_sha256 == null ? "" : var.function_zip_sha256
    output_path  = "${path.module}/.build/querier-fetched.zip"
  }
}

# --- Audit bucket ---

resource "aws_s3_bucket" "audit" {
  bucket        = "${var.name_prefix}-querier-audit-${data.aws_caller_identity.current.account_id}"
  force_destroy = false
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "audit" {
  bucket                  = aws_s3_bucket.audit.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "audit" {
  bucket = aws_s3_bucket.audit.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.audit.id

  rule {
    id     = "expire-audit-records"
    status = "Enabled"

    filter {
      prefix = "audit/"
    }

    expiration {
      days = var.audit_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.audit_retention_days
    }
  }
}

# --- CloudWatch Logs ---

resource "aws_cloudwatch_log_group" "querier" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# --- Lambda function ---

resource "aws_lambda_function" "querier" {
  function_name = local.function_name
  role          = aws_iam_role.querier.arn
  handler       = "querier.handler.lambda_handler"
  runtime       = "python3.12"

  filename         = local.zip_path
  source_code_hash = local.zip_hash

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  environment {
    variables = {
      AUDIT_BUCKET    = aws_s3_bucket.audit.bucket
      MAX_TIMEOUT_S   = tostring(max(var.lambda_timeout_seconds - 5, 5))
      ACCOUNTS_CONFIG = jsonencode(var.spoke_account_roles)
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.querier,
    aws_iam_role_policy.denies,
    aws_iam_role_policy.audit_write,
    aws_iam_role_policy.logs,
  ]

  tags = var.tags
}
