# Local Development Environment

## Overview

Local development happens through three Makefiles:

- The **parent repo's** `Makefile` is the orchestrator. It delegates work
  into the submodules and provides the `make dev` ladder
  (mprocs → tmux → `make -j2`).
- The **backend submodule** (`apps/backend`) ships its own `Makefile` and a
  `docker-compose.yml` running PostgreSQL 18 + RabbitMQ plus the five service
  entries. The dev loop runs the services on the host (`cargo watch`); the
  compose service entries are for `make seed` / deploy images.
- The **web submodule** (`apps/web`) ships its own `Makefile`. Dev runs
  on the host (`pnpm dev`) for the best Next.js HMR experience.

Each submodule must remain runnable on its own
(`cd apps/backend && make dev`, `cd apps/web && make dev`) without the
parent repo. The orchestrator only adds value via the `dev` ladder and
convenience wrappers.

## Compose stack

Backend infra runs in containers from `apps/backend/docker-compose.yml`:

- **PostgreSQL** — image `postgres:18-alpine`, healthchecked. The local stack
  uses a **single database** (`akademiq`) with **one schema per service**
  (`iam`, `billing`, `academic_config`, `academic_ops`, `grading`). Each
  service connects to the same database but selects its schema via the
  `options=-c search_path=<schema>` query param on its `*_DATABASE_URL`.
  Provisioning is handled idempotently by `compose/postgres-init.sql` (first
  boot) and `scripts/bootstrap-db.sh` (called by `make up`); the per-service
  tables themselves are created by that service's refinery migrations, which
  land in the selected schema. This matches the Supabase (dev/prod)
  schema-per-service layout, so the two contexts are structurally identical.
- **RabbitMQ** — image `rabbitmq:3-management-alpine`, AMQP + management
  UI, healthchecked.

The five service crates have their own entries in the same compose file,
built from `Dockerfile.service-template` (the `runtime` stage). These are used
by `make seed` and optional full-in-Docker runs; the day-to-day dev loop runs
the services on the **host** via `cargo watch` (`make dev`), not in containers.

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

The parent repo offers three ways to run backend + web + web-admin together. Pick the
first one that works on your machine:

1. **mprocs (primary)** — `make dev`. Brings Postgres + RabbitMQ up in Docker,
   then reads `mprocs.yaml` and spawns one pane per backend service running
   `cargo watch -x "run -p <svc>"` **on the host** plus `web` and `web-admin`
   panes. Services compile incrementally against one shared `target/`; the host
   env (127.0.0.1 DB/broker URLs, `mold` linker) is exported by the `make dev`
   target. Best per-process scrollback and restart UX.
   `brew install mprocs` (or `cargo install mprocs`).
2. **tmux (fallback)** — `make dev-tmux`. Creates a tmux session
   `akademiq` with three windows running the same commands.
   `Ctrl-b d` detaches; `tmux attach -t akademiq` re-attaches.
   `brew install tmux`.
3. **plain `make -j3` (last resort)** — `make dev-parallel`. No extra
   tooling. Logs from all processes interleave.

Run `make doctor` to check tooling and print install hints. It exits
non-zero only if a *required* tool is missing; mprocs, tmux, `cargo-watch`,
`clang`, and `mold` are advisory.

## Make commands — when to run what

`make dev` is the daily loop and is cheap. The build/test
targets are **SLOW** and guarded: they print a warning and ask before running,
auto-skipping in CI / non-TTY / with `YES=1` (e.g. `YES=1 make build`).

| Command | When to run | Cost |
|---|---|---|
| `make dev` | Daily loop with local DB — every code change (host cargo-watch, infra in Docker) | ~13s/edit, 0.4s no-op |
| `make dev-supabase` | Daily loop with dev Supabase DB (`apps/backend/.env.dev-supabase`) + local RabbitMQ | ~13s/edit, 0.4s no-op |
| `make up` / `make down` | Start/stop Postgres + RabbitMQ | seconds |
| `make migrate` | After adding a migration | fast |
| `make seed` | Once, to load demo data | **SLOW** — minutes (cold) |
| `make build` | Rarely; only to test the release **deploy images** (CI builds these → GHCR) | **SLOW** — ~8 min cold / ~75s per-service change |
| `make test` | Before a PR (full suites). Quick check: `cargo test` in `apps/backend` | **SLOW** — minutes |
| `make test-e2e` | Before a PR touching cross-service flows | **SLOW** — minutes |
| `make test-web` | Web Vitest + Playwright | **SLOW** — minutes |
| `make clean` | Rarely; forces a full cold rebuild next | **SLOW** next build — deletes ~9.5 GB |
| `make purge` | Nuke volumes + artefacts | destructive (confirms) |

`make rebuild` was removed — the host loop (`make dev`) replaced the old
in-container image-rebuild flow.

## Per-service expectations

Each service crate under `apps/backend/services/<name>-service`:

- Has an entry in `apps/backend/docker-compose.yml` built from
  `Dockerfile.service-template` via its `SERVICE_NAME` build arg.
- Reads `DATABASE_URL`, `RABBITMQ_URL`, and its `<SERVICE>_PORT` from
  environment.
- Runs under `cargo watch` on the host in the dev loop (a pane in
  `mprocs.yaml`); the deploy image runs the compiled
  binary directly.
- Exposes a healthcheck endpoint Compose can poll.

Document each service's port and any new env variables in
`apps/backend/.env.example` at the same time.

## Dev reverse-proxy routing (environment-specific)

> **Optional and environment-specific.** One maintainer fronts the local stack
> with Traefik so a single HTTPS origin (`akademiq.dev.sby.test`, LAN IP
> `10.201.0.25`) serves both the web app and the backend APIs. This is **not**
> required — AkademiQ is open source and runs fine on `localhost` with no proxy,
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

## Grading duplicate-evaluation cleanup

Use the backend `akademiq` CLI to inspect and repair duplicate concrete evaluations that can split report formulas:

```bash
cd apps/backend
cargo run -p akademiq-cli -- grading cleanup-evaluations --tenant-id <tenant-id> [--term-id <term-id>] [--homeroom-id <homeroom-id> --subject-id <subject-id>]
cargo run -p akademiq-cli -- grading cleanup-evaluations --tenant-id <tenant-id> [--term-id <term-id>] [--homeroom-id <homeroom-id> --subject-id <subject-id>] --execute
```

The command defaults to report-only. `--execute` deletes gradeless duplicates when exactly one evaluation in the assignment has grades. If all duplicates are gradeless and exactly one code is `SAS`, it keeps `SAS` and deletes the other duplicate evaluations. Other ambiguous assignments are printed for manual review. After cleanup, re-run Generate Draft for affected report-card classes.

## Switching database context (local ↔ dev Supabase)

The backend supports two database contexts during development:

| Context | Database | Connection string host |
|---|---|---|
| `local` | Local Postgres (schema-per-service) | `127.0.0.1:5432` |
| `dev-supabase` | Dev Supabase (schema-per-service) | `*.pooler.supabase.com:5432` |

RabbitMQ always stays local regardless of DB context.

### Why you must purge RabbitMQ on every switch

AkademiQ uses a **transactional outbox** pattern. The outbox publisher polls
`outbox` rows from the current DB and drains them into local RabbitMQ durable
queues (`grading.projections`, `academic-ops.projections`,
`academic-config.projections`). Projection consumers apply these messages by
upserting into projection tables with **no `event_id` dedup check**.

If you switch `*_DATABASE_URL` without purging the broker, messages published
from DB-A will be consumed and applied to DB-B's projection tables — silently
inserting orphan UUIDs that do not exist in the new DB. The only safe guard is
wiping the broker before starting services with a new DB context.

### One-time setup (dev Supabase)

> **Deprecated: `make supabase-sync`.** The prod→dev Supabase sync workflow is
> being retired. To copy production data, use `make db-sync` (prod → local
> Postgres) instead — see [§ Syncing prod data → local Postgres](#syncing-prod-data--local-postgres-make-db-sync).
> The steps below (populating the *dev* Supabase project) remain valid only for
> the `dev-supabase` run context until the sync script is removed.

1. Create the five schemas in your Supabase dev project SQL Editor:

   ```sql
   CREATE SCHEMA IF NOT EXISTS iam;
   CREATE SCHEMA IF NOT EXISTS billing;
   CREATE SCHEMA IF NOT EXISTS academic_config;
   CREATE SCHEMA IF NOT EXISTS academic_ops;
   CREATE SCHEMA IF NOT EXISTS grading;
   ```

2. Decide which connection mode `supabase-sync.sh` will use for `pg_dump` /
   `pg_restore`:

   - **Preferred:** direct connection (`db.<project-ref>.supabase.co:5432`).
     Direct hosts use IPv6 by default; IPv4 direct access requires Supabase's
     paid Dedicated IPv4 add-on.
   - **Fallback:** session pooler (`*.pooler.supabase.com:5432`) if your network
     is IPv4-only and you do not use the IPv4 add-on.

   Copy the exact URL from the Supabase dashboard. Do not use transaction pooler
   port `6543`.

3. Create the dev env file and fill in credentials:

   ```bash
   cd apps/backend
   cp .env.dev-supabase.example .env.dev-supabase
   # edit .env.dev-supabase — replace <dev-project-ref> and PASSWORD
   ```

4. Populate dev DB from prod (run once, repeat whenever you want a fresh copy):

   ```bash
   # Preferred: direct connection (requires IPv6 or paid Dedicated IPv4 add-on)
   PROD_DB_URL=postgres://postgres.<prod-ref>:PASS@db.<prod-ref>.supabase.co:5432/postgres \
   DEV_DB_URL=postgres://postgres.<dev-ref>:PASS@db.<dev-ref>.supabase.co:5432/postgres \
   make supabase-sync

   # Fallback for IPv4-only networks: session pooler :5432 (copy from dashboard)
   PROD_DB_URL=postgres://postgres.<prod-ref>:PASS@aws-1-<region>.pooler.supabase.com:5432/postgres \
   DEV_DB_URL=postgres://postgres.<dev-ref>:PASS@aws-1-<region>.pooler.supabase.com:5432/postgres \
   make supabase-sync
   ```

   `supabase-sync.sh` renames the existing dev schema to
   `<schema>_backup_<timestamp>` before restoring, so you can roll back manually
   if something goes wrong. Old backup schemas are never auto-dropped — clean
   them up manually once you are satisfied:

   ```sql
   DROP SCHEMA iam_backup_20260622_143000 CASCADE;
   -- repeat for each schema
   ```

### Switching context

Use `make db-switch TARGET=<context>`. This single command:

1. Kills all running host-side service binaries (all 5 services)
2. Runs `make up` to ensure Postgres + RabbitMQ are running
3. Full-resets RabbitMQ (`rabbitmqctl reset`) — wipes all queues and messages
4. Prints the exact commands to start services with the new env

```bash
# Switch to dev Supabase
make db-switch TARGET=dev-supabase

# Switch back to local Postgres
make db-switch TARGET=local
```

After the command completes, follow the printed instructions from the repo root:

```bash
# For dev Supabase
make dev-supabase

# For local Postgres
make dev
```

`make dev-supabase` sources `apps/backend/.env.dev-supabase` and does **not**
override the service database URLs back to local Postgres. Do not use plain
`make dev` for the dev Supabase context — it intentionally exports local
`*_DATABASE_URL` values.

Services re-declare the RabbitMQ exchange and queues automatically on boot —
no manual topology setup needed after a purge.

To purge the broker without switching context (e.g. after a crash):

```bash
make rabbitmq-purge
```

### Syncing prod data → local Postgres (`make db-sync`)

`make db-sync` dumps each service schema from the production Supabase database
and restores it into your local Postgres. Because both sides now use the same
schema-per-service layout, this is a near-identical copy. It is the fastest way
to debug against a real dataset without touching the production database.

**Prerequisites:** local infra must be up so the target schemas exist.

```bash
make up
```

**Run it** from the repo root. Only `PROD_DB_URL` is required — `LOCAL_DB_URL`
is built automatically from `apps/backend/.env`
(`POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_PORT` + database `akademiq`):

```bash
# Preferred: direct connection (requires IPv6 or the paid Dedicated IPv4 add-on)
PROD_DB_URL=postgres://postgres.<prod-ref>:PASS@db.<prod-ref>.supabase.co:5432/postgres \
make db-sync

# Fallback for IPv4-only networks: session pooler :5432 (copy from dashboard)
PROD_DB_URL=postgres://postgres.<prod-ref>:PASS@aws-1-<region>.pooler.supabase.com:5432/postgres \
make db-sync
```

Override the local target explicitly if needed:

```bash
PROD_DB_URL=postgres://... \
LOCAL_DB_URL=postgres://akademiq:akademiq_dev@127.0.0.1:54320/akademiq \
make db-sync
```

**Flags** (pass through `--`):

| Flag | Effect |
|---|---|
| `--dry-run` | Preview dump/restore/rename steps without touching either DB |
| `--schema=NAME` | Sync a single schema (repeatable). Default: all five |
| `--skip-verify` | Skip the post-restore prod-vs-local row-count comparison |
| `--keep-dumps` | Keep the `.dump` files in `DUMP_DIR` (default `/tmp`) |

```bash
PROD_DB_URL=postgres://... make db-sync -- --dry-run
PROD_DB_URL=postgres://... make db-sync -- --schema=iam
```

**Safety model.** `db-sync.sh` renames the existing local schema to
`<schema>_backup_<timestamp>` *before* restoring, so a failed restore never
leaves you without data — roll back manually:

```sql
DROP SCHEMA iam CASCADE;
ALTER SCHEMA iam_backup_20260625_120000 RENAME TO iam;
```

Backup schemas are **never auto-dropped**. Clean them up once you are satisfied:

```sql
DROP SCHEMA iam_backup_20260625_120000 CASCADE;
-- repeat for each schema
```

#### Do I need to purge RabbitMQ after a sync?

The outbox publisher drains `outbox` rows from the *current* DB into durable
RabbitMQ queues. If the broker still holds messages from a previous DB context,
projection consumers will apply those orphan events to the freshly-synced local
DB — silently corrupting data. Stop services before syncing, then purge based
on the table below.

| Broker state before sync | Action after `make db-sync` |
|---|---|
| **Dirty** — services ran against another DB context (e.g. `dev-supabase`), or unsure | `make stop && make rabbitmq-purge && make dev` (or one shot: `make db-switch TARGET=local`) |
| **Clean** — broker freshly purged / never used | `make dev` directly |
| **Ragu (unsure)** | Purge to be safe — `make rabbitmq-purge` |

`make db-switch TARGET=local` is the convenience wrapper: it stops services,
runs `make up`, full-resets RabbitMQ, and prints the start command. Use it if
you want the purge guaranteed in one step.

### Connection string conventions

| Usage | Recommended | Fallback | Never use |
|---|---|---|---|
| Backend services (`*_DATABASE_URL`) | Session pooler `*.pooler.supabase.com:5432` | none | Transaction pooler `:6543` |
| `pg_dump` / `pg_restore` (`PROD_DB_URL`, `DEV_DB_URL`) | Direct host `db.<ref>.supabase.co:5432` | Session pooler `*.pooler.supabase.com:5432` if direct is unreachable from IPv4-only networks | Transaction pooler `:6543` |

> `DEV_DB_URL` / `make supabase-sync` are deprecated. For `make db-sync` the
> target is local Postgres (`LOCAL_DB_URL`) and needs no Supabase pooler; the
> `PROD_DB_URL` row above still applies. Never use port `6543` (transaction
> mode) with SQLx or backup/restore workflows — named prepared statements
> collide across backends and billing-service will crash at boot. See
> `.env.prod.example` for the full SQLx rationale.
