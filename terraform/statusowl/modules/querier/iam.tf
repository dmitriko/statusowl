# --- Lambda execution role ---

data "aws_iam_policy_document" "querier_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "querier" {
  name               = "${var.name_prefix}-querier"
  assume_role_policy = data.aws_iam_policy_document.querier_trust.json
  tags               = var.tags
}

# --- Base read-only access ---

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.querier.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

# --- Defense-in-depth denies ---
#
# Layered on top of ReadOnlyAccess. Defends against AWS quietly expanding the
# managed policy, and against sensitive read APIs ReadOnlyAccess does include
# (e.g. iam:GetUser).
#
# Mutating verbs are denied everywhere except the two resources the Lambda's
# own plumbing must write to: the audit-bucket prefix and its log streams.
# We use NotResource on a single Deny rather than trying to "undo" a Deny
# with another Deny — explicit Deny is always final in IAM evaluation.

data "aws_iam_policy_document" "denies" {
  statement {
    sid     = "DenyMutations"
    effect  = "Deny"
    actions = ["*:Create*", "*:Delete*", "*:Update*", "*:Modify*", "*:Put*"]
    not_resources = [
      "${aws_s3_bucket.audit.arn}/audit/*",
      "${aws_cloudwatch_log_group.querier.arn}:*",
    ]
  }

  statement {
    sid    = "DenySensitiveReads"
    effect = "Deny"
    actions = [
      "iam:*",
      "secretsmanager:Get*",
      "ssm:GetParameter*",
      "kms:Decrypt",
      "kms:Get*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "denies" {
  name   = "denies"
  role   = aws_iam_role.querier.id
  policy = data.aws_iam_policy_document.denies.json
}

# --- Cross-account assume role ---

data "aws_iam_policy_document" "assume_spoke" {
  count = length(var.spoke_account_roles) > 0 ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = values(var.spoke_account_roles)
  }
}

resource "aws_iam_role_policy" "assume_spoke" {
  count = length(var.spoke_account_roles) > 0 ? 1 : 0

  name   = "assume-spoke-roles"
  role   = aws_iam_role.querier.id
  policy = data.aws_iam_policy_document.assume_spoke[0].json
}

# --- Audit bucket write (one of the two paths exempted from DenyMutations) ---

data "aws_iam_policy_document" "audit_write" {
  statement {
    sid       = "AuditPutObject"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.audit.arn}/audit/*"]
  }

  statement {
    sid       = "AuditListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.audit.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["audit/*"]
    }
  }
}

resource "aws_iam_role_policy" "audit_write" {
  name   = "audit-write"
  role   = aws_iam_role.querier.id
  policy = data.aws_iam_policy_document.audit_write.json
}

# --- CloudWatch Logs (the other path exempted from DenyMutations) ---

data "aws_iam_policy_document" "logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.querier.arn}:*"]
  }
}

resource "aws_iam_role_policy" "logs" {
  name   = "logs"
  role   = aws_iam_role.querier.id
  policy = data.aws_iam_policy_document.logs.json
}
