# --- Lambda execution role ---

data "aws_iam_policy_document" "mcp_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mcp" {
  name               = "${var.name_prefix}-mcp"
  assume_role_policy = data.aws_iam_policy_document.mcp_trust.json
  tags               = var.tags
}

# --- Invoke querier (the only AWS data permission this Lambda needs) ---
#
# Scoped to the querier ARN. The MCP server itself touches no AWS resources;
# every read goes through the querier under its own narrow IAM.

data "aws_iam_policy_document" "invoke_querier" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [var.querier_function_arn]
  }
}

resource "aws_iam_role_policy" "invoke_querier" {
  name   = "invoke-querier"
  role   = aws_iam_role.mcp.id
  policy = data.aws_iam_policy_document.invoke_querier.json
}

# --- CloudWatch Logs ---

data "aws_iam_policy_document" "logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.mcp.arn}:*"]
  }
}

resource "aws_iam_role_policy" "logs" {
  name   = "logs"
  role   = aws_iam_role.mcp.id
  policy = data.aws_iam_policy_document.logs.json
}
