# AGENTS.md

## Repo state (read first)

This is a parent repo that holds the architecture and product docs **plus**
two git submodules: the backend monorepo at `apps/backend` and the web
frontend at `apps/web`. Both submodules track their upstream `main`. The
parent repo ships an orchestrator (`Makefile` + `mprocs.yaml` + root
`.env.example`) but no Rust crates, no Next.js source, no service
`Cargo.toml`, and no top-level CI config — those live inside each submodule.

When asked to "build", "run", or "test" something, prefer the parent
orchestrator targets (`make dev`, `make up`, `make down`, `make build`,
`make test`) which delegate to the right submodule. For per-service work,
change directory into the relevant submodule. The architecture docs under
`docs/internal/` describe the *intended* system; treat them as the spec
when scaffolding new code, and confirm with the user before adding services
or migrations.

## Submodules

| Mount path     | Repo                                              | Tracks |
|----------------|---------------------------------------------------|--------|
| `apps/backend` | `git@github.com:protocyber/akademiq-backend.git`  | `main` |
| `apps/web`     | `git@github.com:protocyber/akademiq-web.git`      | `main` |

Both repos are private under the `protocyber` GitHub org. SSH access is
required to clone them.

Workflow:

- Fresh clone: `git clone --recurse-submodules git@github.com:protocyber/akademiq.git`
- Existing clone: `git submodule update --init --recursive`
- Pull upstream `main` for a submodule into the parent: `git submodule update --remote --merge apps/backend` (or `apps/web`)

For the backend's internal layout (services, libs), see
`docs/internal/13_engineering_standards/01_repo_structure.md`.

## Local development

The parent repo's `Makefile` is the entry point for cross-submodule work.

| Target              | What it does                                                  |
|---------------------|---------------------------------------------------------------|
| `make dev`          | mprocs (primary): runs `apps/backend` and `apps/web` together |
| `make dev-tmux`     | tmux fallback (`akademiq` session, two windows)               |
| `make dev-parallel` | `make -j2` last-resort fallback (logs interleave)             |
| `make dev-backend`  | only the backend dev loop                                     |
| `make dev-web`      | only the web dev loop                                         |
| `make up` / `down`  | backend infra (Postgres 18 + RabbitMQ) detached               |
| `make build`        | build artefacts in both submodules                            |
| `make test`         | run tests in both submodules                                  |
| `make migrate`      | delegates to backend                                          |
| `make submodules`   | `git submodule update --init --recursive`                     |
| `make doctor`       | checks required tooling and prints install hints              |

Per-machine config lives in three gitignored `.env` files. Each has a
committed `.env.example` you can copy:

- root `.env` — orchestrator paths (`BACKEND_DIR`, `WEB_DIR`,
  `MPROCS_CONFIG`, `TMUX_SESSION`)
- `apps/backend/.env` — Postgres / RabbitMQ ports + credentials, reserved
  Redis slot, future `<SERVICE>_PORT` slots (commented)
- `apps/web/.env` — `WEB_PORT`, `NEXT_PUBLIC_API_BASE_URL`, `NODE_ENV`

`docker-compose.yml` references variables with `${VAR:-default}` so a
missing `.env` does not crash the stack, but `make doctor` will flag it.

Each submodule's `Makefile` is authoritative and works on its own
(`cd apps/backend && make dev`, `cd apps/web && make dev`) without the
parent repo.

## Akademiq CLI guardrails

The `akademiq` binary is an operator/developer convenience CLI, not a
second backend implementation.

- Keep CLI commands thin and operational.
- Reuse existing shared crates for primitives, especially
  `common-auth::hash_password` for IAM password work.
- Prefer existing service HTTP APIs for workflows with domain rules,
  authorization checks, side effects, or events.
- Use direct SQL only for narrow admin maintenance tasks with no required
  domain events, such as listing IAM users or setting a local password hash.
- Do not duplicate service command handlers, repositories, entitlement logic,
  validation workflows, or event publishing in the CLI.
- Wrap existing scripts first when they already own the workflow, such as
  projection bootstrap scripts.
- Keep Makefile focused on lifecycle orchestration: `dev`, `up`, `down`,
  `test`, `build`, `migrate`, `doctor`.
- Prefer CLI commands for parameterized operations: `akademiq iam set-password
  ...`, `akademiq iam users`, `akademiq demo doctor`.
- CLI output must not print secrets, password hashes, tokens, or private keys.
- Commands that mutate data must print the target resource and exit non-zero
  when nothing changed.

## Documentation layout

```
docs/
  internal/    # architecture & engineering specs (13 numbered levels)
  product/     # end-user guides (admin, teacher, student, parent, etc.)
  marketing/   # brochures, presentations, website copy
```

`docs/internal/` is the source of truth for any code generation. Levels are numbered `01_business` through `13_engineering_standards`. Read `docs/internal/README.md` for the level guide. When adding a new doc inside a level, follow the existing `NN_topic.md` numbering.

Diagrams use **Mermaid** in fenced ` ```mermaid ` blocks. Match that style; do not introduce PlantUML or images.

## Service naming (easy to get wrong)

The "Tenant & Subscription Service" in architecture docs is implemented as **billing-service** in code. Per `docs/internal/README.md`:

| Layer | Name |
|---|---|
| Service folder | `/billing-service` |
| Database | `billing_db` |
| Rust crate | `billing_service` |
| API base path | `/api/v1/billing` |
| Event producer | `billing_service` |
| Docker container | `billing-service` |

In prose docs use "Tenant & Subscription (Billing) Service". In code/infra always use `billing*`.

## Target tech stack (when scaffolding code)

From `docs/internal/13_engineering_standards/`:

- Rust + Axum, SQLx against **PostgreSQL 18**, migrations via **refinery** (not sqlx-migrate)
- JWT **RS256**, Argon2 password hashing
- RabbitMQ for events
- `tracing` + OpenTelemetry; every log line must carry `request_id`, `user_id`, `tenant_id`, `service_name`
- Monorepo layout: `/apps/backend/services/<name>-service` and `/apps/backend/libs/common-{auth,db,logging,errors}`
- Required Makefile targets per service: `dev`, `migrate`, `test`, `build`, `up`, `down`
- CQRS: command and query handlers must live in separate modules
- Never trust client-supplied `tenant_id`; resolve from JWT

## API & event conventions

- Base path: `/api/v1/{service}`
- Success envelope: `{ "data": {}, "meta": {} }`
- Error envelope: `{ "error": { "code": "STRING_CODE", "message": "..." } }`
- Validation errors (must align with frontend Zod):
  ```json
  { "error": { "code": "VALIDATION_ERROR", "fields": { "name": ["msg"] } } }
  ```
- Feature-gated endpoints return HTTP 403 with code `FEATURE_NOT_AVAILABLE`
- Event names: `domain.action.past` (e.g. `student.enrolled`); envelope has `event_id`, `event_type`, `occurred_at`, `payload`; breaking changes go through `event_type_v2`

Existing API and event contracts live in `docs/internal/11_integration_contracts/{apis,events}/` — extend these rather than inventing new shapes.

## Working with the docs

- Prefer editing existing files over creating new ones.
- The `docs/internal/README.md` already documents the level structure and the Tenant/Billing naming decision; keep both in sync if either changes.
- ERDs are in `docs/internal/10_data_design/`, one file per service. Component diagrams in `07_components/`, sequences in `08_sequences/`, state machines in `09_states/`. Match the existing per-service file split when adding new ones.

## Git & commit rules

- Never run `git commit` unless the user explicitly asks. No "while we're here" commits.
- Never commit on `main` unless the user explicitly asks for that branch. Default to a feature branch and confirm before pushing.
- Never push to `main` without an explicit ask, even if the commit already exists locally.
- Never `git commit --amend` a commit that has already been pushed, regardless of who authored it.
- Commit messages contain only the message itself. Do not append trailers like `Co-authored-by:`, `Signed-off-by:`, "Generated with ...", tool attributions, or any agent/model identifiers.
- Never run `git push --force` to `main`/`master`. Never bypass hooks (`--no-verify`) unless explicitly asked.
