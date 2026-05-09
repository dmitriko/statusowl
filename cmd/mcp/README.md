# statusowl-mcp

A Model Context Protocol server that exposes the deployed statusowl querier
Lambda as MCP tools. Stdio-only for now; runs on the user's machine and is
registered with Claude Code as a local MCP server. Lambda + Function URL
deployment will land once the tool surface stabilizes.

See [`../../DESIGN.md`](../../DESIGN.md) for the broader architecture.

## Tools

| Tool         | What it does                                                     |
|--------------|------------------------------------------------------------------|
| `run_python` | Runs Python in the querier Lambda for read-only AWS investigation. |

`get_status` and the registry-driven tools land in the next pass.

## Build

All `make` targets live in the repo-root Makefile and are run from there:

```sh
make build-mcp        # writes cmd/mcp/dist/statusowl-mcp
make test-mcp-local   # protocol smoke test (no AWS calls)
make vet-mcp
```

## Configuration

| Var                              | Default     | Purpose                                                     |
|----------------------------------|-------------|-------------------------------------------------------------|
| `STATUSOWL_QUERIER_FUNCTION_NAME`| (required)  | Deployed querier Lambda name or ARN.                        |
| `STATUSOWL_AWS_REGION`           | `us-east-1` | Region for the Lambda Invoke call.                          |
| `STATUSOWL_DEBUG`                | `false`     | Print a ready banner and per-invocation log lines to stderr.|

## AWS credentials

The MCP server itself owns no AWS resources — it just calls
`lambda:InvokeFunction` on the deployed querier. Credentials come from the
standard AWS SDK chain (env vars, `~/.aws/credentials`, SSO, etc.) and need
exactly one permission:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "lambda:InvokeFunction",
    "Resource": "arn:aws:lambda:<region>:<account>:function:<querier-name>"
  }]
}
```

The querier itself enforces all AWS read-only restrictions on the executed
Python — `lambda:InvokeFunction` is just the call-the-querier permission.

## Register with Claude Code

Three places this can live, in order of what you probably want:

### 1. Per-project (preferred while iterating)

Open `~/.claude.json`, find the `projects` map, locate the entry whose key
is the absolute path of the project you'll be `claude`-ing from, and add
`mcpServers` inside that object:

```json
{
  "projects": {
    "/Users/you/code/some-project": {
      "mcpServers": {
        "statusowl": {
          "command": "/Users/you/code/statusowl/cmd/mcp/dist/statusowl-mcp",
          "env": {
            "STATUSOWL_QUERIER_FUNCTION_NAME": "spn-querier",
            "STATUSOWL_AWS_REGION": "us-east-1"
          }
        }
      }
    }
  }
}
```

Scoped to that one project. Best while the binary path and config are
moving. Restart Claude Code after editing.

### 2. Project-local `.mcp.json` (preferred once stable)

Drop a `.mcp.json` at the project root:

```json
{
  "mcpServers": {
    "statusowl": {
      "command": "/absolute/path/to/cmd/mcp/dist/statusowl-mcp",
      "env": {
        "STATUSOWL_QUERIER_FUNCTION_NAME": "spn-querier",
        "STATUSOWL_AWS_REGION": "us-east-1"
      }
    }
  }
}
```

Checkable into git for team-wide config. Caveat: an absolute path to a
locally-built binary makes the file machine-specific. That goes away when
the MCP server gets a release artifact at a predictable install location.

### 3. Global (rare)

Top-level `mcpServers` in `~/.claude.json` — same JSON shape as `.mcp.json`
above, but at the root of the file. Loads in every project, which is
probably not what you want for a server that calls a specific deployed
querier. Mentioned for completeness.

---

After registering: restart Claude Code, confirm `statusowl/run_python`
shows up in `/mcp`, and try *"use statusowl to print the caller identity
from AWS."*

## Layout

```
main.go              entry: bootstrap, register tools, run stdio
config.go            env-var struct + loader
querier.go           AWS Lambda InvokeFunction wrapper (only AWS surface)
run_python.go        run_python tool: input schema, handler, registration
scripts/smoke.sh     protocol-level smoke test (no AWS)
```
