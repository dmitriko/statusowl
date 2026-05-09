data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  function_name = "${var.name_prefix}-mcp"

  # Map our architecture variable to the Go GOARCH the build script expects.
  go_arch = var.lambda_architecture == "arm64" ? "arm64" : "amd64"

  # Source selection. Precedence: explicit path > URL fetch > local build.
  use_zip_path    = var.function_zip_path != null
  use_zip_url     = !local.use_zip_path && var.function_zip_url != null
  use_local_build = !local.use_zip_path && !local.use_zip_url

  zip_path = (
    local.use_zip_path ? var.function_zip_path :
    local.use_zip_url ? data.external.fetch_zip[0].result.path :
    data.external.local_build[0].result.path
  )
  zip_hash = (
    local.use_zip_path ? filebase64sha256(var.function_zip_path) :
    local.use_zip_url ? data.external.fetch_zip[0].result.sha256_b64 :
    data.external.local_build[0].result.sha256_b64
  )
}

# --- Source A: external script fetches from URL and verifies SHA-256 ---

data "external" "fetch_zip" {
  count = local.use_zip_url ? 1 : 0

  program = ["python3", "${path.module}/scripts/fetch-zip.py"]

  query = {
    url          = var.function_zip_url
    expected_sha = var.function_zip_sha256 == null ? "" : var.function_zip_sha256
    output_path  = "${path.module}/.build/statusowl-mcp_lambda_${local.go_arch}.zip"
  }
}

# --- Source B: local-build fallback ---
#
# Unlike the querier (Python, archive_file zips the source), the MCP server
# is Go and needs cross-compilation. Falls back to invoking the same
# scripts/build-mcp.sh that the release workflow uses, then reports the
# resulting zip's path and base64-encoded SHA-256 to Terraform.
#
# Slow (runs `go build` on every plan) and requires Go locally — fine for
# development, not for production. Pin a release URL instead.

data "external" "local_build" {
  count = local.use_local_build ? 1 : 0

  program = ["bash", "${path.module}/scripts/local-build.sh"]

  query = {
    repo_root = "${path.module}/../../../.."
    arch      = local.go_arch
  }
}

# --- CloudWatch Logs ---

resource "aws_cloudwatch_log_group" "mcp" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# --- Lambda function ---

resource "aws_lambda_function" "mcp" {
  function_name = local.function_name
  role          = aws_iam_role.mcp.arn
  # provided.al2023 + handler "bootstrap" is the modern Go-on-Lambda layout.
  # The deterministic zip puts the binary at the archive root as `bootstrap`.
  runtime       = "provided.al2023"
  handler       = "bootstrap"
  architectures = [var.lambda_architecture]

  filename         = local.zip_path
  source_code_hash = local.zip_hash

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  environment {
    variables = {
      # AWS_REGION is auto-set by the Lambda runtime; the MCP server's config
      # picks it up if STATUSOWL_AWS_REGION is unset.
      STATUSOWL_QUERIER_FUNCTION_NAME = var.querier_function_name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.mcp,
    aws_iam_role_policy.invoke_querier,
    aws_iam_role_policy.logs,
  ]

  tags = var.tags
}

# --- Function URL ---
#
# AuthType = AWS_IAM means callers must SigV4-sign their requests. Claude
# Code uses the user's local creds; those need lambda:InvokeFunctionUrl on
# this function's ARN.

resource "aws_lambda_function_url" "mcp" {
  function_name      = aws_lambda_function.mcp.function_name
  authorization_type = "AWS_IAM"
  invoke_mode        = "BUFFERED"
}
