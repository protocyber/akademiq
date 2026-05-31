# AGENTS.md

## Repo state (read first)

This repo currently contains **only documentation**. There is no source code, no `backend/`, no `Cargo.toml`, no `Makefile`, no CI config. Tracked files: `README.md` (one line) and the `docs/` tree.

Do not look for crates, services, migrations, or build commands — they don't exist yet. The architecture docs describe an *intended* future system. When asked to "build", "run", or "test" something, confirm with the user before scaffolding new code, and treat the docs as the spec.

`docs/` is untracked in git as of now. If you add files inside `docs/`, expect them to show up alongside the existing untracked tree on `git status`.

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
- Monorepo layout: `/backend/services/<name>-service` and `/backend/libs/common-{auth,db,logging,errors}`
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
