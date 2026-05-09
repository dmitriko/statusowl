# statusowl Terraform module

Provisions the statusowl read-only AWS-investigation engine. Today: just the
querier Lambda. MCP and Slack will land as additional sub-modules; the root
module is structured to absorb them without a refactor.

See [`../../DESIGN.md`](../../DESIGN.md) for the broader architecture.

## Usage

```hcl
module "statusowl" {
  source = "github.com/dmitriko/statusowl//terraform/statusowl"

  name_prefix = "statusowl"

  # Single-account install: omit this. Multi-account: map model-facing
  # account name to the spoke role ARN.
  spoke_account_roles = {
    prod = "arn:aws:iam::111111111111:role/statusowl-readonly"
    dev  = "arn:aws:iam::222222222222:role/statusowl-readonly"
  }

  audit_retention_days   = 90
  lambda_memory_mb       = 512
  lambda_timeout_seconds = 90

  # In CI: build the zip in your pipeline, set its path here.
  # Locally: leave null and the module zips cmd/querier/src/ for you.
  function_zip_path = null
}

output "querier_role_arn" {
  value = module.statusowl.querier_role_arn
}
```

## Cross-account setup

The querier runs in your hub account. To investigate spoke accounts, each
spoke needs a `statusowl-readonly` role that trusts the querier's role.

This module does **not** create the spoke role — that lives in the spoke and
is outside statusowl's read-only mandate. Create it once per spoke (manually
or with your own Terraform), then add it to `spoke_account_roles`.

```hcl
# In each spoke account.
resource "aws_iam_role" "statusowl_readonly" {
  name = "statusowl-readonly"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        # Paste module.statusowl.querier_role_arn from the hub account here.
        AWS = "arn:aws:iam::<hub-account-id>:role/<name_prefix>-querier"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.statusowl_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
```

Once the spoke role exists, add it to `spoke_account_roles` in the hub-side
module block and re-apply.

## Building the Lambda zip

Two paths.

**Default — `function_zip_path = null`.** The module's `archive_file` data
source zips `cmd/querier/src/` at plan time. Convenient for iteration. Has
the usual `archive_file` caveats: it runs every plan, the hash drifts as
local files do, and it doesn't reproduce in CI.

**CI — build the zip yourself, pass `function_zip_path`.**

```sh
cd cmd/querier
mkdir -p build/pkg
cp -r src/querier build/pkg/
# (Add `uv pip install --target build/pkg -r requirements.txt` if you ever
# add runtime deps. boto3 is provided by Lambda; nothing else today.)
( cd build/pkg && zip -r ../querier.zip . )
```

…then point the module at `cmd/querier/build/querier.zip`. Stable hash,
faster plans, no archive_file surprises.

## Security boundary recap

The querier role:

- attaches the AWS-managed `ReadOnlyAccess` policy
- denies `*:Create*`, `*:Delete*`, `*:Update*`, `*:Modify*`, `*:Put*`
  everywhere except the audit-bucket `audit/` prefix and the Lambda's own
  CloudWatch log streams (which it must write to)
- denies `iam:*`, `secretsmanager:Get*`, `ssm:GetParameter*`, `kms:Decrypt`,
  `kms:Get*` everywhere
- can call `sts:AssumeRole` only on ARNs in `spoke_account_roles`

Audit log: `s3://<audit-bucket>/audit/YYYY/MM/DD/{uuid}.json` — one record
per invocation including the generated code, args, stdout/stderr, duration,
and caller identity. Retention is `audit_retention_days` (default 90).

## Inputs / outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf).
