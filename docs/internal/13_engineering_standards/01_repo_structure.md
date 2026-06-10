# Repository Structure (Backend Monorepo)

The backend monorepo is mounted in the parent repo as a submodule at
`apps/backend`. Inside that submodule the layout is:

```
/apps/backend
  Cargo.toml                 # workspace root
  features.toml              # canonical plan ↔ feature matrix
  docker-compose.yml         # local stack (Postgres + RabbitMQ + services)
  compose.test.yml           # isolated stack used by `make test-e2e`
  compose/postgres-init.sql  # bootstraps per-service databases
  /services
    /iam-service             ✓ phase 1
    /billing-service         ✓ phase 1
    /academic-config-service ✓ phase 2
    /academic-ops-service    ✓ phase 3
    /grading-service         🚧 phase 4
    /attendance-service      ⏳ phase 5+
    /promotion-service       ⏳ phase 5+
    /notification-service    ⏳ phase 5+
  /libs
    /common-auth             ✓ phase 1 (RS256 JWT, Argon2id, extractors)
    /common-db               ✓ phase 1 (SQLx pool, refinery runner, with_tx)
    /common-logging          ✓ phase 1 (tracing JSON + request_id)
    /common-errors           ✓ phase 1 (AppError + envelope)
    /common-testing          ✓ phase 1 (testcontainers, JWT mint)
  /tests
    /e2e                     ✓ phase 1 (cross-service compose-driven crate)
  /tools
    /akademiq-cli            ✓ operator/developer CLI (`akademiq` binary)
```

Each service is independently buildable and deployable. The phase
roadmap and which change delivers each phase live in
[`16_implementation_phases.md`](./16_implementation_phases.md).

The web frontend (Next.js) lives in a separate submodule at `apps/web`
(`git@github.com:protocyber/akademiq-web.git`) and is out of scope for
this document. See `apps/web/CONVENTIONS.md` for its rules.

## Cargo workspace conventions

- Shared dependencies are declared once in `[workspace.dependencies]`
  and consumed by member crates with `dep = { workspace = true }`.
  Adding a dep means editing `apps/backend/Cargo.toml` first.
- Every service is a binary crate with a `[lib]` target that exposes
  the same code for in-process integration tests. Tests use
  `tower::ServiceExt::oneshot` against the `Router` directly so they
  do not need a network listener.
- Service migrations live under `services/<name>/migrations/` and are
  embedded with `refinery::embed_migrations!("migrations")`.
- Per-service Makefiles (one per crate) follow the standard target
  list in [`12_makefile_standards.md`](./12_makefile_standards.md).
- Operator/developer utilities live under `tools/` and must stay thin:
  reuse shared crates for primitives, call service APIs for domain workflows,
  and use direct SQL only for narrow admin maintenance tasks with no required
  domain events.
