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

# --- Deny IAM enumeration ---
#
# ReadOnlyAccess is the base. The only meaningful gap it leaves open is IAM
# read access (iam:GetUser, iam:ListRoles, etc.) — which lets an attacker
# map the security model. Deny it.
#
# We dropped broader cross-service mutation/secret denies: AWS rejects
# vendor-wildcard actions like "*:Put*" in regular IAM policies, and the
# value-add over ReadOnlyAccess turned out to be small enough not to be
# worth the brittleness.

data "aws_iam_policy_document" "denies" {
  statement {
    sid       = "DenyIAMEnumeration"
    effect    = "Deny"
    actions   = ["iam:*"]
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

# --- Audit write into the shared bucket ---
#
# Scoped to the audit/ prefix only. ListBucket is conditioned on s3:prefix
# so the querier can't enumerate cache/* either.

data "aws_iam_policy_document" "audit_write" {
  statement {
    sid       = "AuditPutObject"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.shared.arn}/audit/*"]
  }

  statement {
    sid       = "AuditListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.shared.arn]
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

# --- CloudWatch Logs ---

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
