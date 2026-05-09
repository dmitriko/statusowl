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

```sh
uv sync
make test
make local-run                                  # uses scripts/sample_event.json
make local-run EVENT=path/to/your/event.json
```

`make local-run` mocks S3 with `moto`; nothing touches real AWS.

> **Heads up on subprocess isolation.** `moto` patches boto3 inside the
> parent process, but the handler runs your code in a child interpreter,
> which doesn't see the mock. The sample event therefore avoids AWS calls.
> For end-to-end local exercises with real AWS calls, either point at a
> `moto_server` endpoint via `AWS_ENDPOINT_URL` or use real credentials.

## Environment variables

| Var                | Default | Purpose                                     |
|--------------------|---------|---------------------------------------------|
| `AUDIT_BUCKET`     | (req'd) | S3 bucket for `audit/YYYY/MM/DD/{uuid}.json`|
| `ACCOUNTS_CONFIG`  | `""`    | JSON: `{"prod": "arn:aws:iam::...:role/..."}` |
| `MAX_TIMEOUT_S`    | `60`    | Hard upper bound for `timeout_seconds`      |
| `DEFAULT_TIMEOUT_S`| `30`    | Used when event omits `timeout_seconds`     |
| `MEM_LIMIT_MB`     | unset   | RLIMIT_AS for the child (Linux only)        |

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
