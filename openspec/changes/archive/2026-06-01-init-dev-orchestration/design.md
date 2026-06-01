## Context

`apps/backend` and `apps/web` were just added as submodules with only a `README.md`
and `.gitignore` each (see archived change `init-backend-frontend-submodules`).
Before any service or page work can start, contributors need a working
`make dev` story for both submodules and an orchestrator at the parent repo
that runs them together.

The architecture spec under `docs/internal/13_engineering_standards/` is
prescriptive about a few things:

- `12_makefile_standards.md` — every service (and by extension each submodule
  root) ships a `Makefile` with `dev`, `migrate`, `test`, `build`, `up`, `down`.
- `11_devops_local_setup.md` — every service supports Docker Compose with
  PostgreSQL, RabbitMQ, and the service container; standard ports must be
  documented.
- `02_tech_stack.md` — PostgreSQL **18**, SQLx, refinery, RabbitMQ, tracing +
  OpenTelemetry, "Docker + Docker Compose" container baseline.
- `01_repo_structure.md` — backend monorepo holds `services/<name>-service`
  and `libs/common-{auth,db,logging,errors}`; the Makefile and compose files
  must work today (with no services) and survive once those crates are added.

Stakeholders: backend engineers (Rust/Axum), frontend engineers (Next.js),
future CI, AI agents working from `AGENTS.md`. The user explicitly chose:

- mprocs as the primary orchestrator, tmux as fallback, `make -j2` as last
  resort.
- `docker compose --watch` for backend dev (auto-refresh).
- Host `pnpm dev` for web (Next.js fast-refresh).
- pnpm as the Node package manager.
- `.env`-driven configuration for ports/credentials so they can be customized
  without editing tracked files.
- Each submodule must remain independently deployable without the parent repo.

Constraints:

- `apps/backend` and `apps/web` are git submodules. Edits there are commits in
  separate repos. The parent repo only commits a pinned SHA after each
  submodule's own commit lands.
- The parent repo today has no `Makefile`, no `.env.example`, no orchestrator
  config. Nothing depends on those files yet, so we can introduce them
  freely.
- `docker compose watch` requires Docker Compose v2.22+. macOS contributors
  using Docker Desktop ≥ 4.24 already have it; Linux contributors may need a
  newer compose plugin.

## Goals / Non-Goals

**Goals:**

- One command (`make dev` from the parent repo) brings up Postgres + RabbitMQ
  + (eventually) all services + the web frontend, with hot-reload on both
  sides.
- Standard Makefile target list works in each submodule today and tomorrow:
  no rewrite needed when the first service crate or Next.js page lands.
- Every port and credential is read from `.env` (gitignored) with a
  documented default in `.env.example` (committed). Three `.env.example`
  files: root, `apps/backend`, `apps/web`.
- Each submodule's `Makefile` and Docker artefacts work standalone:
  `cd apps/backend && make build` and `cd apps/web && make build` produce
  deployable artefacts without the parent repo.
- Three orchestrator paths so contributors are never blocked by missing
  tooling: mprocs primary, tmux fallback, `make -j2` last resort.
- `make doctor` tells a contributor what's missing before they fail
  cryptically inside compose or pnpm.

**Non-Goals:**

- No Cargo workspace, no service crates, no `common-*` libs inside
  `apps/backend`. Services are scaffolded in follow-up changes.
- No `create-next-app`, no Tailwind, no Zod, no real Next.js source in
  `apps/web`. Frontend scaffold is a follow-up change.
- No Redis/Valkey container today. The `.env.example` reserves a
  `REDIS_PORT` slot for future use; no actual service is added.
- No CI changes. CI is handled in a separate change that consumes the
  Makefile targets defined here.
- No observability stack containers (Tempo, Loki, Grafana). Tracing is
  configured per-service later; the local stack today is just Postgres +
  RabbitMQ.
- No production deployment topology. The Dockerfile in `apps/web` builds a
  production image but how it ships is out of scope.

## Decisions

### Decision 1: mprocs is the primary orchestrator, tmux is fallback, `make -j2` is last resort

`make dev` runs `mprocs --config mprocs.yaml`, which spawns two named processes
("backend" and "web") each running the submodule's `make dev`. Logs scroll
independently per pane, `Ctrl-r` restarts a single process, `Ctrl-q` quits all.

`make dev-tmux` runs `tmux new-session -s akademiq -n dev` and creates two
windows running the same commands. Detach with `Ctrl-b d`. Useful when
`mprocs` isn't installed.

`make dev-parallel` runs `make -j2 dev-backend dev-web` and interleaves logs.
Last resort with zero extra dependencies.

**Rationale:** mprocs is purpose-built for "two long-running dev processes
with separate scrollback" and ships great per-process restart. tmux is
universally available and lets a contributor detach the session. `-j2` works
on a fresh machine with nothing installed but make + git.

**Alternatives considered:**

- Overmind / hivemind (Procfile-based) — extra Ruby/Go install, less
  ergonomic than mprocs.
- Docker Compose for the web app too — slow HMR on macOS due to filesystem
  sync, diverges from typical Next.js workflow.
- Foreman — same issues as overmind, plus no scrollback per process.

### Decision 2: `docker compose watch` for backend dev, host `pnpm dev` for web

Backend `make dev` (in `apps/backend`) calls
`docker compose --env-file .env up --build --watch`. Compose's
`develop.watch` rules under each service's compose entry rebuild the image
when its sources change. Postgres + RabbitMQ + every (future) service runs
in a container.

Web `make dev` (in `apps/web`) calls `pnpm dev` directly. Next.js fast
refresh runs on the host. Production builds use `Dockerfile`, but dev does
not.

**Rationale:** The backend dev path matches the deploy path 1:1 — exactly
what `02_tech_stack.md` and `11_devops_local_setup.md` assume. The web dev
path uses Next.js's native HMR, which is the dominant Next.js workflow and
is dramatically faster on macOS than bind-mounted compose.

**Alternatives considered:**

- `cargo watch` on host — faster incremental rebuilds, but needs Rust
  toolchain installed and the dev path diverges from deploy.
- Compose for web too — covered above.

### Decision 3: One `.env` per scope, ports/credentials read from environment

Three `.env.example` files, all committed, all small:

- **Root `.env.example`**: defines variables consumed by the orchestrator.
  Includes `BACKEND_DIR=apps/backend`, `WEB_DIR=apps/web`, anything mprocs
  reads.
- **`apps/backend/.env.example`**: `POSTGRES_PORT`, `POSTGRES_USER`,
  `POSTGRES_PASSWORD`, `POSTGRES_DB_PREFIX` (each service gets a separate
  DB), `RABBITMQ_PORT`, `RABBITMQ_MGMT_PORT`, `RABBITMQ_USER`,
  `RABBITMQ_PASSWORD`, reserved `REDIS_PORT`, plus `<SERVICE>_PORT` slots
  for the eight services in `06_container_architecture` (commented out
  until a service exists).
- **`apps/web/.env.example`**: `WEB_PORT`, `NEXT_PUBLIC_API_BASE_URL`,
  `NODE_ENV`.

`.env` is gitignored at every level. `Makefile`s use `include .env` (with
`-include` to no-op if missing) and export the variables via `export`.
`docker-compose.yml` references variables with `${VAR}` and supplies a
default with `${VAR:-default}` so a missing `.env` doesn't crash compose.

**Rationale:** A contributor who already has `5432` taken can change one
file and move on. Multi-environment support (local/dev/staging/prod) is
already in `13_engineering_standards/05_environment_strategy.md` — using
plain `.env` here is the simplest thing that satisfies "customize ports
without editing tracked files."

**Trade-off:** Three `.env.example` files instead of one. Accepted because
each submodule must work standalone, which means each owns its own
variables.

### Decision 4: Standard Makefile targets in each submodule, root delegates

Each submodule's `Makefile` ships the full `12_makefile_standards.md` set:
`dev`, `migrate`, `test`, `build`, `up`, `down`. Targets are functional
today (placeholders for `migrate`/`test` print a "not yet wired" message
and exit 0 so CI doesn't break) and become real when the first service or
Next.js page lands.

The root `Makefile`'s targets are thin delegators:

```
dev-backend:   $(MAKE) -C apps/backend dev
dev-web:       $(MAKE) -C apps/web dev
up:            $(MAKE) -C apps/backend up
down:          $(MAKE) -C apps/backend down
build:         $(MAKE) -C apps/backend build && $(MAKE) -C apps/web build
test:          $(MAKE) -C apps/backend test && $(MAKE) -C apps/web test
```

`dev`, `dev-tmux`, `dev-parallel`, `submodules`, `doctor` are the
orchestrator-specific targets that do not delegate.

**Rationale:** Independent deployability requires each submodule's Makefile
to be authoritative. The root layer adds value only via the orchestrator
and via convenience wrappers. Reproduces no logic.

### Decision 5: `make doctor` is best-effort and prints actionable hints

A `doctor` target checks for `docker`, `docker compose` (v2.22+), `pnpm`
(via corepack), `node` (matches `.nvmrc`), `git`, and optionally `mprocs`
and `tmux`. For each missing tool it prints the install hint
(`brew install mprocs`, `corepack enable`, etc.). It exits non-zero only
if a *required* tool is missing; mprocs/tmux are advisory.

**Rationale:** First-run friction is the biggest DX risk for a multi-tool
stack. A scriptable doctor catches that without trying to install anything.

### Decision 6: pnpm pinned via Corepack, not via global install

`apps/web/package.json` declares `"packageManager": "pnpm@<exact>"` and
ships an `.nvmrc` for Node. `make dev` runs `corepack enable` (idempotent,
needs Node ≥ 16.13) and then `pnpm install` + `pnpm dev`.

**Rationale:** Locks pnpm version to whatever the repo committed. No
"works on my machine" from version skew. Standard Next.js shop convention.

### Decision 7: Web `Dockerfile` is production-only, not used in dev

`apps/web/Dockerfile` is a multi-stage build (`node:lts-slim` →
`pnpm build` → `node:lts-slim` runtime, with `output: 'standalone'`
ready). It exists so `cd apps/web && make build` produces a deployable
image without the parent repo. Dev does not use it.

**Rationale:** Independent deployability requires the artefact to live
inside the submodule. Dev uses host pnpm because compose-on-macOS hurts
HMR.

### Decision 8: Backend `docker-compose.yml` contains only Postgres + RabbitMQ today

No service entries yet. When the first service crate lands, that change
adds a `services.iam-service` block with a `develop.watch` stanza
referencing its source dir and `Dockerfile.service-template` as the build
context. The pattern is documented as a comment block in
`docker-compose.yml` so the next change is mechanical.

**Rationale:** Keep this change small and reversible. Locking in the
infra containers and the watch convention is enough to unblock the next
change.

### Decision 9: Doc updates limited to one new section in `11_devops_local_setup.md`, plus README/AGENTS

`11_devops_local_setup.md` today is nine lines. We extend it to describe
the new orchestrator, the `.env.example` files, the standard ports, and
the mprocs/tmux/`-j2` ladder — without changing its scope. Other docs in
`docs/internal/` are untouched.

`AGENTS.md` gets a new "Local development" section (orchestrator targets,
env-file convention) so agents pick the right command. Root `README.md`
gains a "Quick start" block.

**Rationale:** Avoids spec churn. The architectural docs already mandate
the Makefile target list and Docker baseline; we are implementing them,
not re-defining them.

## Risks / Trade-offs

- **Risk: `docker compose watch` requires v2.22+** → Mitigation:
  `make doctor` checks the version and tells the user how to upgrade.
  Documented in `11_devops_local_setup.md`.
- **Risk: macOS Docker volume mounts make even backend rebuilds slow** →
  Mitigation: `--watch` rebuilds the *image* (not bind-mount), which is
  fine for Rust where rebuild dominates anyway. Cargo build cache lives
  inside the image as a named volume.
- **Risk: pnpm via corepack confuses contributors used to global pnpm** →
  Mitigation: `make doctor` prints the corepack hint; `README.md` "Quick
  start" calls out `corepack enable`.
- **Risk: Three `.env.example` files drift out of sync** → Mitigation:
  Each is small and scoped; cross-references in comments. A sanity check
  in `make doctor` warns if `.env` is missing keys present in
  `.env.example`.
- **Risk: mprocs not on every contributor's machine** → Accepted. tmux
  and `make -j2` are the documented fallbacks.
- **Risk: Submodule SHA bumps on every Makefile/compose tweak** →
  Accepted. We're at the start of the project; both submodules will see
  frequent commits anyway. The parent only bumps when a contributor
  decides to.
- **Risk: `make doctor` becomes stale when new tools are added** →
  Mitigation: Doctor lives in the root `Makefile`; updating it is part
  of any change that introduces a new dev dependency. Listed as a
  follow-up rule in `AGENTS.md`.
- **Trade-off: Two dev paths (containerized backend, host frontend)** →
  Accepted. Matches the dominant convention for each stack and avoids
  the macOS HMR penalty.

## Migration Plan

This is greenfield scaffolding; there is nothing to migrate from. Rollout:

1. Land changes in `apps/backend` (PR in submodule):
   `Makefile`, `docker-compose.yml`, `.dockerignore`, `.env.example`,
   `Dockerfile.service-template`, `.gitignore` updates. Verify
   `cd apps/backend && make up && make down` works on a clean checkout.
2. Land changes in `apps/web` (PR in submodule): `Makefile`,
   `package.json`, `.nvmrc`, `.env.example`, `Dockerfile`,
   `.dockerignore`, `.gitignore` updates. Verify
   `cd apps/web && pnpm install && make dev` boots on a free port.
3. Land changes in this parent repo: `Makefile`, `mprocs.yaml`,
   `.env.example`, `.gitignore` updates, `README.md`, `AGENTS.md`,
   `docs/internal/13_engineering_standards/11_devops_local_setup.md`,
   submodule SHA bumps. Verify `make submodules && make dev` works on a
   fresh clone.

**Rollback:**

- Submodule changes: revert the submodule PRs. Parent repo's pinned SHAs
  fall back to the previous commit on the next `git submodule update`.
- Parent repo changes: revert this PR. The submodules still have their
  Makefiles, but the orchestrator goes away and `make dev` no longer
  exists at the root.

## Open Questions

- None blocking. Future considerations (out of scope here):
  - Whether to add a Redis/Valkey container when the first service
    needing a cache lands.
  - Whether to add a single `observability` profile to compose
    (Tempo/Loki/Grafana) or keep that in a separate compose file.
  - Whether to split web `Dockerfile` into dev + prod variants if a
    contributor really wants containerized web dev.
