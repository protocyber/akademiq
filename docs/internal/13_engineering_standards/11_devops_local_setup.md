# Local Development Environment

## Overview

Local development happens through three Makefiles:

- The **parent repo's** `Makefile` is the orchestrator. It delegates work
  into the submodules and provides the `make dev` ladder
  (mprocs → tmux → `make -j2`).
- The **backend submodule** (`apps/backend`) ships its own `Makefile` and a
  `docker-compose.yml` running PostgreSQL 18 + RabbitMQ. Each service crate
  is added as another compose entry by future changes.
- The **web submodule** (`apps/web`) ships its own `Makefile`. Dev runs
  on the host (`pnpm dev`) for the best Next.js HMR experience.

Each submodule must remain runnable on its own
(`cd apps/backend && make dev`, `cd apps/web && make dev`) without the
parent repo. The orchestrator only adds value via the `dev` ladder and
convenience wrappers.

## Compose stack

Backend infra runs in containers from `apps/backend/docker-compose.yml`:

- **PostgreSQL** — image `postgres:18-alpine`, healthchecked. Each
  microservice will own its own database
  (`<service>_db`) created via that service's
  refinery migrations.
- **RabbitMQ** — image `rabbitmq:3-management-alpine`, AMQP + management
  UI, healthchecked.

Service containers are added to the same compose file when their crates
land. The file already documents the canonical `develop.watch` block in a
commented service template so the next change adding `iam-service` is
mechanical.

## Port and credential customization

All ports, users, and passwords live in `.env` files. Each `.env` is
gitignored; `.env.example` is committed with safe defaults.

```
.env                    # parent: BACKEND_DIR, WEB_DIR, MPROCS_CONFIG, TMUX_SESSION
apps/backend/.env       # POSTGRES_*, RABBITMQ_*, reserved REDIS_PORT, <SERVICE>_PORT slots
apps/web/.env           # WEB_PORT, NEXT_PUBLIC_API_BASE_URL, NODE_ENV
```

`docker-compose.yml` references variables with `${VAR:-default}`, so a
missing `.env` will not crash compose. The default ports are:

| Service               | Variable             | Default |
|-----------------------|----------------------|---------|
| Web (Next.js dev)     | `WEB_PORT`           | `3000`  |
| PostgreSQL 18         | `POSTGRES_PORT`      | `5432`  |
| RabbitMQ AMQP         | `RABBITMQ_PORT`      | `5672`  |
| RabbitMQ management   | `RABBITMQ_MGMT_PORT` | `15672` |
| Redis (reserved)      | `REDIS_PORT`         | `6379`  |
| `<service>` HTTP      | `<SERVICE>_PORT`     | t.b.d.  |

The source of truth for the canonical default values is each
`.env.example`. Service ports (`IAM_PORT`, `BILLING_PORT`, etc.) are
reserved as commented-out lines and become live as their crates land.

## Orchestrator: `make dev` ladder

The parent repo offers three ways to run backend + web together. Pick the
first one that works on your machine:

1. **mprocs (primary)** — `make dev`. Reads `mprocs.yaml`, spawns named
   processes "backend" and "web", each running its submodule's `make dev`.
   Best per-process scrollback and restart UX.
   `brew install mprocs` (or `cargo install mprocs`).
2. **tmux (fallback)** — `make dev-tmux`. Creates a tmux session
   `akademiq` with two windows running the same commands.
   `Ctrl-b d` detaches; `tmux attach -t akademiq` re-attaches.
   `brew install tmux`.
3. **plain `make -j2` (last resort)** — `make dev-parallel`. No extra
   tooling. Logs from both processes interleave.

Run `make doctor` to check tooling and print install hints. It exits
non-zero only if a *required* tool is missing; mprocs and tmux are
advisory.

## Per-service expectations

Once service crates land under `apps/backend/services/<name>-service`,
each service:

- Adds an entry to `apps/backend/docker-compose.yml` (the commented
  template in that file shows the canonical shape).
- Defines a `develop.watch` rule pointing at its `src/` so
  `docker compose watch` rebuilds + restarts only its container on file
  change.
- Reads `DATABASE_URL`, `AMQP_URL`, and its `<SERVICE>_PORT` from
  environment.
- Exposes a healthcheck endpoint Compose can poll.

Document each service's port and any new env variables in
`apps/backend/.env.example` at the same time.

## Dev reverse-proxy routing (environment-specific)

> **Optional and environment-specific.** One maintainer fronts the local stack
> with Traefik so a single HTTPS origin (`akademiq.dev.sby.test`, LAN IP
> `10.201.0.25`) serves both the web app and the backend APIs. This is **not**
> required — AcademiQ is open source and runs fine on `localhost` with no proxy,
> on your own domain, or behind a different proxy. The reference config lives in
> the parent repo at `infra/traefik/` (see `infra/traefik/README.md`).

In that setup, Traefik routes by path prefix:

| Path                        | Service                 | Port | Priority |
|-----------------------------|-------------------------|------|----------|
| `/api/v1/iam/*`             | iam-service             | 8081 | 100      |
| `/api/v1/billing/*`         | billing-service         | 8082 | 100      |
| `/api/v1/academic-config/*` | academic-config-service | 8083 | 100      |
| `/api/v1/academic-ops/*`    | academic-ops-service    | 8084 | 100      |
| `/api/v1/grading/*`         | grading-service         | 8086 | 100      |
| everything else             | web (Next.js)           | 3009 | 1        |

Because the proxy handles path routing, the web client uses absolute
same-origin base URLs and needs no Next.js rewrite. The live Traefik instance
is owned by the shared `surabaya-dev/traefik` repo, which bind-mounts the
akademiq fragment (`infra/traefik/akademiq.dynamic.yaml`) and keeps the shared
`redirect-https` middleware + TLS certs.

**Adding a new backend service** means adding its Traefik mapping (a
`PathPrefix(/api/v1/<name>)` router at `priority: 100` plus a matching service
entry) to `infra/traefik/akademiq.dynamic.yaml`, in lockstep with the
docker-compose entry and the `<SERVICE>_PORT` in `apps/backend/.env.example`.
