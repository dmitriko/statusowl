# querier

statusowl's Python Lambda. Runs LLM-generated Python under bounded execution
with an S3 audit log. The only component allowed to execute generated code.

See `../../DESIGN.md` for the broader architecture.

## Event shape

```json
{
  "code": "print('hello')",
  "timeout_seconds": 30,
  "account": "prod"
}
```

`account` is optional. When set, the Lambda assumes the role mapped in
`ACCOUNTS_CONFIG` and exposes it to the child process via `AWS_*` env vars.

## Local dev

All `make` targets live in the repo-root Makefile and are run from there:

```sh
make install-querier
make test-querier
make local-run-querier                                  # uses scripts/sample_event.json
make local-run-querier QUERIER_EVENT=path/to/event.json
```

`local-run-querier` mocks S3 with `moto`; nothing touches real AWS.

> **Heads up on subprocess isolation.** `moto` patches boto3 inside the
> parent process, but the handler runs your code in a child interpreter,
> which doesn't see the mock. The sample event therefore avoids AWS calls.
> For end-to-end local exercises with real AWS calls, either point at a
> `moto_server` endpoint via `AWS_ENDPOINT_URL` or use real credentials.

## Environment variables

| Var                | Default | Purpose                                                  |
|--------------------|---------|----------------------------------------------------------|
| `STATUSOWL_BUCKET` | (req'd) | Shared statusowl bucket. Querier writes only `audit/*`.  |
| `ACCOUNTS_CONFIG`  | `""`    | JSON: `{"prod": "arn:aws:iam::...:role/..."}`            |
| `MAX_TIMEOUT_S`    | `60`    | Hard upper bound for `timeout_seconds`                   |
| `DEFAULT_TIMEOUT_S`| `30`    | Used when event omits `timeout_seconds`                  |
| `MEM_LIMIT_MB`     | unset   | RLIMIT_AS for the child (Linux only)                     |

Audit objects are written to `audit/YYYY/MM/DD/{uuid}.json` inside the
bucket. The `cache/` prefix in the same bucket is reserved for the future
MCP module — querier IAM has no access to it.

## Layout

```
src/querier/
  handler.py       Lambda entry point: validate → run → audit
  executor.py      subprocess runner with timeout/memory/output bounds
  audit.py         S3 audit log writer
  accounts.py      account map + assume-role session resolution
  identity.py      sts:GetCallerIdentity for audit records
  config.py        env-var accessors
tests/             pytest + moto
scripts/
  invoke_local.py  CLI: invoke handler against moto-mocked AWS
```
