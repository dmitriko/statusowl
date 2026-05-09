# statusowl Terraform module

Provisions the statusowl read-only AWS-investigation engine. Today: querier
Lambda + MCP server (Lambda + Function URL, opt-in). Slack will land as the
last sub-module.

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

  # Querier artifact (see "Choosing a Lambda artifact source" below).
  function_zip_url    = "https://github.com/dmitriko/statusowl/releases/download/querier-v0.1.0/querier.zip"
  function_zip_sha256 = "<paste from querier.zip.sha256 in the release>"

  # MCP server (Lambda + Function URL). Default: enabled. Set to false for
  # stdio-only deployments where every user runs the MCP binary locally.
  enable_mcp              = true
  mcp_function_zip_url    = "https://github.com/dmitriko/statusowl/releases/download/mcp-v0.1.0/statusowl-mcp_lambda_arm64.zip"
  mcp_function_zip_sha256 = "<paste from the matching .sha256 in the release>"
  mcp_lambda_architecture = "arm64"   # Graviton — flip to x86_64 if you must.
}

output "querier_role_arn"  { value = module.statusowl.querier_role_arn }
output "mcp_function_url"  { value = module.statusowl.mcp_function_url }
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

## MCP server

The MCP sub-module is opt-in (`enable_mcp`, default `true`). It deploys the
Go MCP server as a Lambda with a Function URL, `AuthType = AWS_IAM`. The
Lambda's role has `lambda:InvokeFunction` on the querier and CloudWatch
Logs writes — nothing else.

The same set of artifact-source rules applies (path > URL > local build),
but with the variables prefixed `mcp_`:

```hcl
mcp_function_zip_url    = "https://github.com/.../mcp-v0.1.0/statusowl-mcp_lambda_arm64.zip"
mcp_function_zip_sha256 = "..."
mcp_lambda_architecture = "arm64"   # must match the zip's architecture
```

Output `mcp_function_url` is what Claude Code points its remote-MCP config
at. Callers must be granted `lambda:InvokeFunctionUrl` on the function ARN.
A copy-pasteable IAM snippet for that lives in
`cmd/mcp/README.md` § *Register with Claude Code (remote Lambda)*.

The "local build" fallback for MCP runs `scripts/build-mcp.sh KIND=lambda`
on every plan via an `external` data source. Fine for development; pin a
release URL in production.

## Choosing a Lambda artifact source

Three paths, in order of recommendation.

### 1. Production — pin a release URL + SHA-256

Each `querier-v*` tag publishes a deterministic `querier.zip` and a sidecar
`querier.zip.sha256` to GitHub Releases. Pin both:

```hcl
function_zip_url    = "https://github.com/dmitriko/statusowl/releases/download/querier-v0.1.0/querier.zip"
function_zip_sha256 = "489bfd84fe2041b00906dd5b668777eed26eea08417154ba5a0d4c7630c65448"
```

The module fetches the zip at plan time and refuses to deploy if the SHA-256
doesn't match. The release notes include a copy-pasteable HCL snippet.

### 2. CI — build the zip yourself, pass `function_zip_path`

For air-gapped setups, internal artifact mirrors, or pipelines that want
release artifacts to come from their own build infrastructure. Use the same
script the release workflow uses, so artifacts are bit-identical:

```sh
./scripts/build-querier.sh
# writes cmd/querier/build/querier.zip + querier.zip.sha256
```

Then in your root module:

```hcl
function_zip_path = "${path.module}/cmd/querier/build/querier.zip"
```

`function_zip_path` takes precedence over `function_zip_url` if both are set.

### 3. Development — let the module zip the source tree

When neither `function_zip_url` nor `function_zip_path` is set, the module's
`archive_file` data source zips `cmd/querier/src/` at plan time. Convenient
while iterating locally; the hash drifts as you edit files, every plan
rebuilds, and it isn't reproducible across machines. Don't use in CI.

### Precedence

```
function_zip_path  >  function_zip_url  >  archive_file (built-in default)
```

The module deterministically picks one; setting more than one is allowed but
only the highest-precedence value takes effect.

## Storage layout

A single S3 bucket — `${name_prefix}-statusowl-${account_id}` — backs all
statusowl components. Prefix-separated, IAM-segmented:

| Prefix              | Writer  | Lifecycle                     |
|---------------------|---------|-------------------------------|
| `audit/YYYY/MM/DD/` | querier | `audit_retention_days` (90d)  |
| `cache/code/`       | MCP*    | (lands with the MCP module)   |
| `cache/result/`     | MCP*    | (lands with the MCP module)   |

\* MCP module not implemented yet — `cache/*` paths are reserved.

The querier's IAM is scoped to `audit/*` only; it has no read or write
access to `cache/*`. The bucket name and ARN are exposed as outputs
(`bucket_name`, `bucket_arn`) so the future MCP sub-module can scope its
own IAM to its prefixes.

## Security boundary recap

The querier role:

- attaches the AWS-managed `ReadOnlyAccess` policy
- denies `iam:*` to block security-model enumeration (the one meaningful
  gap ReadOnlyAccess leaves open)
- gets a narrow Allow for `s3:PutObject` on `audit/*` and the corresponding
  `s3:ListBucket` (prefix-conditioned), and for `logs:CreateLogStream` /
  `logs:PutLogEvents` on its own log group — and nothing else write-side
- can call `sts:AssumeRole` only on ARNs in `spoke_account_roles`

Audit log: `s3://${name_prefix}-statusowl-${account_id}/audit/YYYY/MM/DD/{uuid}.json`
— one record per invocation including the generated code, args,
stdout/stderr, duration, and caller identity. Retention is
`audit_retention_days` (default 90).

## Inputs / outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf).
