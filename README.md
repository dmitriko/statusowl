# statusowl

A read-only AWS investigation agent for MCP-capable coding agents.

[**See the design and the reasoning →**](./DESIGN.md)

---

## What it actually does

You ask your coding agent (we use Claude Code mostly) about your AWS environment in plain English.
statusowl makes it run sandboxed Python (boto3, narrow IAM) against your
account and synthesize an answer. It investigates instead of just listing.
The examples below use Claude Code, but the MCP server is standard and can
be used from other MCP-capable agents too.

A real example, lightly anonymized:

> **You:** what is the current status of the ecs cluster `preview`?

> **Agent (via statusowl):**
>
> Cluster `preview` — ACTIVE
> Fargate-only · Container Insights enabled
> Tasks: 24 running / 0 pending · Services: 24 active, all desired=running (1/1)
>
> ⚠️ 3 services with FAILED rollouts (current task is still running, but the
> latest deploy never stabilized):
>
> | Service                     | Last failure         | Failed tasks |
> |-----------------------------|----------------------|--------------|
> | preview-a1b2c3-worker-svc   | 2026-05-08 11:03 UTC | 3            |
> | preview-d4e5f6-worker-svc   | 2026-05-05 14:19 UTC | 3            |
> | preview-g7h8i9-worker-svc   | 2026-05-01 20:20 UTC | 3            |
>
> All three are `*-worker-svc` across the three env prefixes (a1b2c3, d4e5f6,
> g7h8i9). Same failure mode — "tasks failed to start" after target-group
> deregistration. Worth checking the worker task definition / target group
> health-check config; this looks systemic rather than per-env.

That's not a list of API responses. It's an investigation: list cluster,
join with services, find rollout failures, group by failure mode, surface a
pattern across envs. One round trip.

> **You** investigate why  preview-g7h8i9-worker-svc is failing exactly   

> **Agent (via statusowl):**
Gives you exact the reason why it's failing and what to do to fix it.
---

## Why it's safe

LLM-generated code is genuinely scary in an AWS account. statusowl's design
puts a real boundary between the model and your infrastructure:

- **Querier Lambda** runs every line of model-written Python. Read-only IAM
  managed policy, plus an explicit deny on `iam:*` to prevent enumerating
  the security model. No internet egress beyond AWS APIs. Bounded execution.
- **Audit log** in S3: every invocation records the code, args, stdout/stderr,
  duration, and caller identity.
- **Multi-account** via assume-role — the querier holds no spoke-account
  permissions itself; spoke accounts grant a narrow read-only role to the
  querier and that's the only path.

You can rotate, delete, or scope the querier role without touching anything
else. No "agent on my laptop with my dev creds" for any AWS read.

---

## Quickstart

Two parts: deploy the Lambda, then point your coding agent at it via MCP.

### 1. Deploy the Lambda

**Prereqs:** AWS account you can `terraform apply` into, Terraform ≥ 1.5,
AWS credentials with permission to create IAM roles, S3 buckets, and
Lambdas. Takes ~5 minutes.

In your existing Terraform (or a fresh root module):

```hcl
module "statusowl" {
  source = "github.com/dmitriko/statusowl//terraform/statusowl?ref=querier-v1.0.2"

  name_prefix         = "myteam"
  function_zip_url    = "https://github.com/dmitriko/statusowl/releases/download/querier-v1.0.2/querier.zip"
  function_zip_sha256 = "7e709b86b5e870d5b76cc271b274f8209a15c1f99354bfaa3cdb8fb5d148f858"

  spoke_account_roles  = {}    # empty for single-account; see below for multi-account
  audit_retention_days = 90
}

output "querier_function_name" {
  value = module.statusowl.querier_function_name
}
```

Then:

```sh
terraform init
terraform apply
```

Smoke-test the deploy:

```sh
aws lambda invoke \
  --function-name "$(terraform output -raw querier_function_name)" \
  --payload '{"code": "import boto3; print(boto3.client(\"sts\").get_caller_identity())", "timeout_seconds": 30}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/out.json
cat /tmp/out.json
```

You should see the querier's assumed-role identity and an `audit_id` field.
The audit record now lives in S3.

### 2. Run the MCP server locally

**Prereqs:** an MCP-capable coding agent; AWS credentials on your machine
with `lambda:InvokeFunction` permission on the deployed querier; a binary
from the [releases page](https://github.com/dmitriko/statusowl/releases) or
a Go toolchain to build from source.

Download the `statusowl-mcp` binary for your platform from the releases
page, or build:

```sh
git clone https://github.com/dmitriko/statusowl
cd statusowl/cmd/mcp && make build-mcp
# binary lands at ./dist/statusowl-mcp
```

Register the server with your agent's MCP client. For Claude Code, in
`~/.claude.json`, locate `projects[<your-project-path>]` and add an
`mcpServers` entry inside that project object:

```json
"mcpServers": {
  "statusowl": {
    "command": "/absolute/path/to/statusowl-mcp",
    "env": {
      "STATUSOWL_QUERIER_FUNCTION_NAME": "myteam-querier",
      "STATUSOWL_AWS_REGION": "us-east-1"
    }
  }
}
```

Restart your agent if needed. From a Claude Code session in that project:

```
> use statusowl to print the AWS caller identity
```

If the round trip works, you're done. Ask it real questions about your
infrastructure.

### Multi-account

The querier holds no permissions in your spoke accounts. Each spoke creates
a narrow read-only role that trusts the querier:

```hcl
# in the spoke account's terraform
resource "aws_iam_role" "statusowl_readonly" {
  name = "statusowl-readonly"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { AWS = "<paste querier_role_arn from the home account>" }
      Action    = "sts:AssumeRole"
    }]
  })
  managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

  inline_policy {
    name = "deny-iam"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{ Effect = "Deny", Action = "iam:*", Resource = "*" }]
    })
  }
}
```

Then add the spoke to your home-account module call:

```hcl
spoke_account_roles = {
  prod = "arn:aws:iam::222222222222:role/statusowl-readonly"
  dev  = "arn:aws:iam::333333333333:role/statusowl-readonly"
}
```

The model passes `account: "prod"` to the querier's `run_python`; the
querier assumes the matching role for that invocation only.

---

## Architecture

For the design and the reasoning behind every choice, see
[DESIGN.md](./DESIGN.md). Short version:

- **`statusowl-querier`** (Python Lambda) — runs LLM-generated code under
  narrow IAM. Audit log to S3. The security boundary.
- **`statusowl-mcp`** (Go) — MCP server. Runs as a local stdio binary or
  as a Lambda fronted by an Function URL (Header-based auth). Translates MCP
  tool calls into querier invocations.

A native Slack connector was scoped out — MCP-capable coding agents already
cover the chat surface well, and adding a second front door bloats the
trust model without adding capability.

---

## License

MIT.
