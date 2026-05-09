# envscout — Design

Repo: `github.com/dmitriko/envscout` (public, MIT)

A read-only agent for inspecting AWS environments. Consumed through Claude
Code via MCP and Skills, with a thin Slack adapter for non-technical users.

---

## Goals

- Answer *"is `<env>` ready / did the deploy break?"* in seconds.
- Work uniformly across stable envs (`prod`, `dev`) and ephemeral slates
  (short-living application testing environments).
- Open source, useful to other teams from day one, while solving a real
  problem for one specific team from day one.

## Non-goals

- Mutate anything. Reads only.

---

## Cornerstones

Two ideas the design rests on:

1. **GitHub is the source of truth for project configuration.** Registry,
   accounts, deployment-specific skills — all in a GitHub repo. Updates flow
   through PR review, like any other team artifact. Not a database, not a
   UI, not a runtime API.

2. **The engine is three Lambdas.** `envscout-slack` receives chat events,
   `envscout-mcp` serves tools, `envscout-querier` runs LLM-generated code.
   Each has its own IAM role; none stores state. Everything persistent
   (skills, registry, audit log) lives in Git or S3.

---

## Stages

User journey, three stages. Each is a skill in the template repo.

1. **Bootstrap.** Clone template, `cd`, run claude, type "bootstrap." The
   skill orients the user, confirms inputs (Slack? multi-account?), and
   writes a `module "envscout"` block ready to drop into their existing
   Terraform.

2. **Deploy.** User adds the module to their TF, runs `terraform apply`.
   One module covers querier (always), MCP (optional), Slack (optional).
   Outputs include role ARNs the user wires into spoke accounts' trust
   policies.

3. **Build registry.** Skill uses the deployed querier to walk AWS
   (LLM-generated Python, narrow IAM, no shell composition). Proposes
   probes, writes `registry.yaml`, `accounts.yaml`, `<org>-envs` skill.
   User reviews `git diff`, commits.

After stage 3, ongoing use is just talking to the bot. Adding accounts or
envs later means re-running stage 3 against new creds, or hand-editing
the registry.

---

## Architecture

```
                   ┌──────────────────────┐
                   │ envscout-registry    │  CLI: init / sync / validate
                   └──────────┬───────────┘
                              ▼
                   GitHub config repo
                   (registry.yaml, accounts.yaml, skills)
                              │
                  ┌───────────┴───────────┐
                  ▼                       ▼
            read by MCP             loaded by Claude Code (auto)
                                    loaded by Slack agent (via prompt)

   ┌─────────────────────┐
   │ envscout-slack      │  Go Lambda. Slack ⇄ MCP glue.
   │ (Slack connector)   │
   └──────────┬──────────┘
              │ MCP
   Claude     │
   Code  ─────┼────────▶ ┌──────────────────────┐
              ▼          │ envscout-mcp         │  Go Lambda. Hot path.
                         │ (MCP server)         │  Reads registry. Read-only AWS.
                         └────┬───────────┬─────┘
                              │           │ run_python (invoke)
                         read │           ▼
                         AWS  │   ┌────────────────────┐
                              │   │ envscout-querier   │  Python Lambda.
                              │   │ (query executor)   │  Narrow IAM. Audit log.
                              │   └────────────────────┘
                              ▼
                           AWS APIs
```

### Why three Lambdas

- **Slack vs MCP.** Slack has a 3-second ack window and channel-listening
  semantics; MCP has tool-call semantics. Different shapes; combining them
  bloats either.
- **MCP vs querier.** MCP runs handwritten, reviewed code. Querier runs
  LLM-generated Python under narrow IAM. Different trust levels need
  different IAM roles, which means different Lambdas.

### Why MCP + Skills

Team-specific knowledge lives in *Skills*; team-specific execution logic
lives in MCP *tools*. Both are portable: Claude Code and the Slack agent
consume the same skills and the same MCP server.

---

## Skills

The model's primary knowledge surface.

### Knowledge skills (always present)

- **`envscout-concepts`** — generic, ships in template repo. Explains the
  envscout model: envs, probes, slates, how to interpret `get_status`,
  when to reach for `run_python`. Stable.
- **`<org>-envs`** — deployment-specific, written during stage 3. Summarizes
  the team's envs: names, patterns, conventions, gotchas. References
  `registry.yaml`.

### Stage skills (one per journey stage)

- **`bootstrap`** — stage 1. Orient, gather inputs, write `module "envscout"` block.
- **`deploy`** — stage 2. Walk user through `terraform apply`, verify outputs.
- **`build-registry`** — stage 3. Use querier to walk AWS, write registry.

Stage skills can be removed or marked done after completion.

All skills are loaded by Claude Code automatically (progressive disclosure:
name + description always in context, body loaded on demand). For the Slack
agent, knowledge-skill bodies are injected into the system prompt — we own
that prompt.

PR-gated. Skill changes are a normal review.

---

## Registry

YAML file in the config repo. Describes how to *find* each env's resources
(probes), not what they are.

### Probes

Each entry has *probes*: predicates matching AWS resources. An env's
contents are the union of what its probes match.

Considered alternatives, both rejected:

1. List contents explicitly. Falls apart for dynamic envs and naming drift.
2. Single AWS-tag selector. Falls apart when naming is inconsistent across
   resource types (e.g., infra tasks `{id}-{service}`, app tasks
   `slate-{id}-{service}`, plus name truncation at 32 chars).

Probes embrace mess. Lenient by design.

### One shape, static and dynamic

Static envs have probes with no captures. Dynamic envs use capture variables
(`{id}`) extracted from the requested env name.

```yaml
- name: prod
  account: prod
  cluster: spin-prod
  probes:
    - task_pattern: "*"

- name_pattern: "slate-{id}"
  account: dev
  cluster: slate
  probes:
    - task_pattern: "{id}*-*"           # infra tasks
    - task_pattern: "slate-{id}*-*"     # app tasks
  id_prefix_min_length: 7               # tolerate AWS name truncation
```

`get_status("slate-pr-1234")` matches the pattern, fills `id`, runs probes,
returns the union.

The `<org>-envs` skill summarizes the registry for the model. The MCP server
reads the same registry to resolve probes at tool-call time.

### Multi-account

Each entry references an account from `accounts.yaml`:

```yaml
accounts:
  prod: { id: "111...", role: "arn:aws:iam::111...:role/envscout-readonly" }
  dev:  { id: "222...", role: "arn:aws:iam::222...:role/envscout-readonly" }
```

Querier assumes the per-account role. MCP server stays in its home account.
Hub-and-spoke trust topology, scales trivially.

The cross-account `envscout-readonly` role is created out-of-band by the
user (Terraform, console — outside envscout's read-only mandate). The
bootstrap skill provides the trust policy snippet and instructions; it does
not create the role itself.

During bootstrap, Claude can only walk accounts the user has local creds
for. Other accounts are either: (a) visited later by switching profile and
re-running bootstrap, or (b) declared manually in `accounts.yaml` with a
TODO marker for envs to fill in.

### Onboarding

The user clones the template repo (via `gh` or plain `git clone`), `cd`s
in, runs `claude`, and types "bootstrap." The journey from there is the
five stages described above.

```
$ git clone https://github.com/dmitriko/envscout-template my-team-envscout-config
$ cd my-team-envscout-config && rm -rf .git && git init
$ claude
> bootstrap
```

Stage 3 (build registry) is where probes get written. It uses the deployed
querier rather than local Bash — generated Python runs in a single
predictable execution per question, instead of multi-round-trip shell
composition that fights `column`, `xargs`, and quoting.

The `envscout-registry` CLI exists for scripted/CI use (`init`, `sync`,
`validate`) but is optional. Most users never run it directly.

For teams with TF state in S3 or TF Cloud, stage 3 detects this and offers
to parse state files instead of (or in addition to) walking live AWS via
the querier. Either path produces the same artifact.

---

## Tools

### `get_status(env, focus?)`

Primary tool. Optimized for the polling case ("is it ready / did it break").

- `env`: name of an env, static or dynamic.
- `focus`: enum, narrows the check. Configurable per deployment; defaults:
  `all | infra | services | data | network`.

Returns short, scannable text — typically 3–8 lines. Not an investigation
tool; deeper drilling happens via `run_python`.

### `run_python(code, timeout_seconds?)`

Escape hatch. Model writes Python, querier runs it under narrow IAM. boto3
in scope; common stdlib only by default.

Exists for the long tail of unique questions. "Compare CPU across three
slates", "list slates older than 24h with an outdated backend" — these
don't fit fixed shapes. Coarse tools handle the 80%; `run_python` handles
the rest without ballooning the surface.

### Why both

`get_status` is faster (cached, no LLM round-trip), returns consistent
shapes, encodes team-specific health logic. `run_python` is the flexibility
valve. Each is bad at the other's job.

---

## Code generation flow

`get_status` is partly code generation:

1. MCP loads EnvDef for the env (probes → AWS resources).
2. Cache key: `hash(env_def_values, focus)`.
3. If cached: fetch Python from S3, send to querier with current EnvDef.
4. If not: call LLM with EnvDef shape + focus, ask for
   `def status(env_def): ...`. Cache. Send to querier.
5. Querier runs, returns result.
6. MCP returns result to caller.

### Caching

Key is hash of EnvDef *values*, not just env name. Env evolves over time
(services added, tasks rotated); hash changes when contents change → fresh
code generated. Same env unchanged → cache hit.

S3 backend. No DynamoDB unless we have a reason.

A separate, shorter-TTL result cache (~30s) handles the polling case.

---

## Security boundary: the querier

Only component running LLM-generated code.

- **Narrow IAM.** Read-only managed policy plus explicit denies on
  `*:Create*`, `*:Delete*`, `*:Put*`, `*:Update*`, `*:Modify*`. Defends
  against AWS quietly expanding ReadOnlyAccess.
- **No internet egress.** AWS APIs only. Closes "exfiltrate via DNS / HTTP".
- **Bounded execution.** Hard CPU/memory/time limits.
- **Audit log.** Every invocation: timestamp, code, args, stdout/stderr,
  duration, caller identity.
- **Cross-account via assume-role.** Querier assumes per-account read-only
  role per request. Generated code uses the assumed-role session.

MCP runs only handwritten, reviewed code; broader IAM is fine because the
surface is small and known.

---

## Repos

Three repos:

```
envscout/                           ← public, MIT, github.com/dmitriko/envscout
  cmd/registry/                      ← CLI (optional, for scripted use)
  cmd/mcp/                           ← Go MCP server
  cmd/querier/                       ← Python Lambda
  cmd/slack/                         ← Go Slack connector
  terraform/envscout/                ← TF module: querier + optional MCP/Slack
  internal/...

envscout-template/                  ← public, github.com/dmitriko/envscout-template
  skills/envscout-concepts/          ← generic knowledge skill
  skills/bootstrap/                  ← stage 1 skill
  skills/deploy/                     ← stage 2 skill
  skills/build-registry/             ← stage 3 skill
  registry.yaml                      ← empty, filled in stage 3
  accounts.yaml                      ← empty, filled in stage 3
  README.md

<your-org>-envscout-config/         ← private, deployment-specific
  registry.yaml
  accounts.yaml
  skills/<org>-envs/
  skills/envscout-concepts/          ← copied from template
  custom_focus.yaml                  ← optional
```

The framework knows nothing about specific environments, ARNs, or naming
conventions. All of that lives in the config repo.

Any commit to the public repos mentioning a real env name, ARN, or account
is a regression. CI grep is cheap insurance.

---

## What lives where (at runtime)

- **Model context.** Skill descriptions always; bodies on demand. Tool
  descriptions always.
- **MCP server memory.** Loaded registry. Reloaded on cold start or
  explicit reload.
- **Querier memory.** Nothing persistent.
- **S3.** Code cache (per env-def hash + focus). Audit log. Result cache.
- **Config repo.** `registry.yaml`, `accounts.yaml`, deployment skill.
  Source of truth.

---

## Plan

Build order roughly mirrors the user journey.

- `envscout-template` repo: `envscout-concepts` skill, three stage skills,
  empty registry/accounts files, README.
- TF module `terraform/envscout/`: querier (always), MCP (optional, default
  on), Slack (optional, default off). Outputs role ARNs and endpoint URLs.
- Querier Lambda: narrow IAM, audit log, assume-role for multi-account.
- `bootstrap` skill: orient, write `module "envscout"` block.
- `deploy` skill: walk user through `terraform apply`, verify outputs.
- `build-registry` skill: probe proposal via querier, file generation.
- MCP server with `get_status` and `run_python`. Code cache (S3, hashed
  by EnvDef values + focus). Result cache.
- Slack connector. Channel mode where the bot reads every message and
  decides when to respond. Audit log at the chat layer, separate from
  querier audit.
- `envscout-registry` CLI: `init` / `sync` / `validate` for scripted use.
- TF-state-as-source for stage 3 and CLI.
- Multi-account exercised end-to-end.
- Provisioned concurrency on the MCP server once usage is interactive.

---

## Component summary

The engine — three Lambdas:

| Component           | Language | Runtime  | Purpose                   |
|---------------------|----------|----------|---------------------------|
| `envscout-slack`    | Go       | Lambda   | Slack connector           |
| `envscout-mcp`      | Go       | Lambda   | MCP server, hot path      |
| `envscout-querier`  | Python   | Lambda   | Sandboxed code execution  |

Plus a CLI for build-time work:

| Component           | Language | Runtime  | Purpose                   |
|---------------------|----------|----------|---------------------------|
| `envscout-registry` | TBD      | CLI      | Build/maintain registry   |

LLM: Bedrock with Anthropic models. Stays inside AWS for IAM, billing,
egress.
