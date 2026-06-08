## Why

The two submodules at `apps/backend` (Rust/Axum) and `apps/web` (Next.js) currently
contain only `README.md` + `.gitignore`. There is no path for a contributor to run
`make dev` and see anything — no Makefiles, no `docker-compose.yml`, no orchestrator
in the parent repo. The architecture spec in `docs/internal/13_engineering_standards/`
already mandates Docker Compose per service, the standard Makefile target list
(`dev`, `migrate`, `test`, `build`, `up`, `down`), and PostgreSQL 18 + RabbitMQ as
the local infra. We need to land that scaffolding so future service work has a
working dev loop on day one, while keeping each submodule independently deployable
without the parent repo present.

## What Changes

- **`apps/backend` (submodule):** add `Makefile` (with `dev`, `up`, `down`,
  `migrate`, `test`, `build` placeholders that work today and survive the eventual
  service crates), `docker-compose.yml` (PostgreSQL 18, RabbitMQ, named app network),
  per-service `Dockerfile` skeleton template, `.dockerignore`, and `.env.example`.
  `make dev` runs `docker compose up --build --watch` so any change under
  `services/` and `libs/` triggers a rebuild + restart of the affected container.
  No service crates yet — those land in follow-up changes.
- **`apps/web` (submodule):** add `Makefile` (`dev`, `start`, `build`, `test`,
  `lint`, `up`, `down` aliases), `package.json` minimal stub with `pnpm` as the
  package manager (`packageManager: pnpm@<pinned>`), `.nvmrc`, `.env.example`,
  `Dockerfile` (production multi-stage build, used for deploy not dev), and
  `.dockerignore`. `make dev` runs `pnpm dev` on the host (Next.js fast-refresh).
  No Next.js scaffold yet.
- **Parent repo (root):** add `Makefile` orchestrator with:
  - `make dev` — starts both apps via **mprocs** as the primary path, reading
    `mprocs.yaml` (committed at root). Each pane runs the submodule's own
    `make dev`.
  - `make dev-tmux` — same layout via tmux as a zero-extra-install fallback.
  - `make dev-parallel` — `make -j2 dev-backend dev-web` last-resort fallback that
    interleaves logs.
  - `make submodules` — `git submodule update --init --recursive`.
  - `make up` / `make down` — backend infra only (delegates to `apps/backend`).
  - `make doctor` — checks `docker`, `docker compose`, `pnpm`, `node`, `mprocs` (with
    install hints), `tmux`, and required ports.
- **Port and credential customization via `.env`:** every port (web, API gateway,
  each service stub, Postgres, RabbitMQ, future Redis) is read from `.env`
  with documented defaults in `.env.example`. The root has its own `.env.example`
  consumed by `mprocs.yaml` and the orchestrator targets. Each submodule has its
  own `.env.example` consumed by its `Makefile` and `docker-compose.yml`.
  `.env` files are gitignored; `.env.example` is committed.
- **Docs:** update `docs/internal/13_engineering_standards/11_devops_local_setup.md`
  to point at the new `apps/backend/docker-compose.yml`, document the orchestrator,
  and list the standard ports (in prose; the source of truth is each `.env.example`).
  Update root `README.md` with a "Quick start" `make dev` block. Update `AGENTS.md`
  to mention the new orchestrator targets and the mprocs/tmux/`-j2` ladder.

Non-goals (kept narrow on purpose):

- No Rust crate scaffolding, no Cargo workspace, no service code.
- No `create-next-app`, no Tailwind, no Zod, no real Next.js source.
- No Redis container yet (the `.env.example` reserves a `REDIS_PORT` slot but no
  service is added). Add only when a service actually needs it.
- No CI changes.

## Capabilities

### New Capabilities

- `dev-orchestration`: defines how a contributor brings up the full local
  development stack (backend infra + backend services + web frontend), how
  ports/credentials are configured via `.env` files, and the command surface
  (`make dev`, `make dev-tmux`, `make dev-parallel`, `make doctor`,
  `make submodules`, `make up`, `make down`) for both the parent repo and each
  submodule. It also defines that each submodule must be runnable on its own
  (`apps/backend && make dev`, `apps/web && make dev`) without the parent repo.

### Modified Capabilities

<!-- None. The companion `repo-layout` capability from
`init-backend-frontend-submodules` has not been archived into
`openspec/specs/` yet, so requirements about Makefiles/Docker/orchestrator
are owned by the new `dev-orchestration` capability rather than via a delta. -->


## Impact

- **Affected files in this repo:** new `Makefile`, `mprocs.yaml`, `.env.example`,
  `.gitignore` updates (ignore `.env`); modified `README.md`, `AGENTS.md`,
  `docs/internal/13_engineering_standards/11_devops_local_setup.md`.
- **Affected files in `apps/backend`:** new `Makefile`, `docker-compose.yml`,
  `.dockerignore`, `.env.example`, `Dockerfile.service-template`,
  `.gitignore` update.
- **Affected files in `apps/web`:** new `Makefile`, `package.json` (minimal),
  `.nvmrc`, `.env.example`, `Dockerfile`, `.dockerignore`, `.gitignore` update.
- **Contributor workflow:** copy `.env.example` → `.env` in each location,
  install `pnpm` (corepack), Docker Desktop ≥ 4.24 / compose ≥ 2.22 (for
  `--watch`), optionally `mprocs`, then `make dev`.
- **Independent deployability:** each submodule's `Makefile` and `docker-compose.yml`
  are self-contained. `cd apps/backend && make build` produces deployable images
  with no parent repo dependency. `cd apps/web && make build` produces a
  production Next.js bundle / Docker image with no parent dependency.
- **Downstream changes unblocked:** Cargo workspace + first service crate,
  Next.js scaffold, shared CI templates, observability stack
  (`tracing`/OpenTelemetry collector container).
