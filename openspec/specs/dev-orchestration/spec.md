## ADDED Requirements

### Requirement: Parent repo provides a `make dev` orchestrator with mprocs as primary, tmux as fallback, and `make -j2` as last resort

The parent repo SHALL ship a root `Makefile` whose `dev` target launches both
the backend submodule and the web submodule together, in that priority order.

- `make dev` MUST run mprocs against a committed `mprocs.yaml` that defines
  exactly two named processes: one running `$(MAKE) -C apps/backend dev` and
  one running `$(MAKE) -C apps/web dev`.
- `make dev-tmux` MUST start a tmux session named `akademiq` with two windows
  running the same two commands. The session MUST be detachable.
- `make dev-parallel` MUST run `$(MAKE) -j2 dev-backend dev-web` and exit when
  the contributor sends `Ctrl-C`.
- `make dev-backend` and `make dev-web` MUST be standalone delegators that
  call `$(MAKE) -C apps/backend dev` and `$(MAKE) -C apps/web dev`
  respectively.

#### Scenario: Contributor with mprocs installed runs `make dev`

- **WHEN** a contributor with mprocs on `PATH` runs `make dev` from the
  parent repo root after `cp .env.example .env` in all three locations
- **THEN** mprocs starts and shows two named panes: "backend" running
  `apps/backend/Makefile`'s `dev` target and "web" running
  `apps/web/Makefile`'s `dev` target

#### Scenario: Contributor without mprocs uses tmux fallback

- **WHEN** a contributor without mprocs runs `make dev-tmux`
- **THEN** a tmux session named `akademiq` starts with two windows running
  the backend and web `dev` targets, and `Ctrl-b d` detaches without killing
  either process

#### Scenario: Contributor with neither mprocs nor tmux uses parallel make

- **WHEN** a contributor without mprocs and without tmux runs
  `make dev-parallel`
- **THEN** `make` runs both submodule `dev` targets concurrently with
  interleaved log output and exits cleanly when both child processes stop

### Requirement: Backend submodule `make dev` runs Postgres + RabbitMQ + services in Docker with auto-refresh

The `apps/backend` submodule SHALL ship a `Makefile` whose `dev` target brings
up the local infra stack and all (current and future) services in Docker
Compose with file-watching enabled.

- `make dev` MUST resolve to `docker compose --env-file .env up --build
  --watch` against `apps/backend/docker-compose.yml`.
- `docker-compose.yml` MUST define services for `postgres` (image
  `postgres:18` or pinned newer minor) and `rabbitmq` (image with management
  plugin), and MUST reserve placeholder structure for the eight microservices
  named in `docs/internal/06_container_architecture/AcademiQ_Container_Diagram.md`.
- Every service entry that the change adds today MUST consume its port,
  username, password, and database name from environment variables resolved
  via `apps/backend/.env`.
- The compose file MUST include a documented `develop.watch` example block
  (commented or under a stub service) so the next change adding a real
  service crate is mechanical.

#### Scenario: `make dev` boots Postgres and RabbitMQ on configured ports

- **WHEN** a contributor copies `apps/backend/.env.example` to
  `apps/backend/.env`, optionally edits `POSTGRES_PORT` and `RABBITMQ_PORT`,
  and runs `cd apps/backend && make dev`
- **THEN** `docker compose` starts containers `postgres` and `rabbitmq`
  bound to the ports listed in `.env`, and a contributor can connect to
  Postgres at `localhost:${POSTGRES_PORT}` and the RabbitMQ management UI
  at `localhost:${RABBITMQ_MGMT_PORT}`

#### Scenario: Editing a Rust source file triggers a watch rebuild

- **GIVEN** a future change has added a service crate at
  `apps/backend/services/iam-service/` with a `develop.watch` rule pointing
  at its `src/` directory
- **WHEN** `make dev` is running and a contributor edits a file under
  `apps/backend/services/iam-service/src/`
- **THEN** Docker Compose rebuilds and restarts only the `iam-service`
  container; other containers continue running

### Requirement: Web submodule `make dev` runs `pnpm dev` on the host with Next.js fast refresh

The `apps/web` submodule SHALL ship a `Makefile` whose `dev` target runs the
Next.js dev server on the contributor's host (not in Docker).

- `make dev` MUST run `corepack enable` (idempotent) and then `pnpm install`
  followed by `pnpm dev`.
- `package.json` MUST declare `"packageManager": "pnpm@<exact-version>"` and
  the repo MUST ship an `.nvmrc` pinning the Node version.
- The dev server MUST bind to `WEB_PORT` from `apps/web/.env` (default
  `3000`).
- The Next.js production `Dockerfile` MUST exist for deploys but MUST NOT be
  used by `make dev`.

#### Scenario: `make dev` boots Next.js on a configured port

- **WHEN** a contributor sets `WEB_PORT=4000` in `apps/web/.env` and runs
  `cd apps/web && make dev`
- **THEN** the Next.js dev server starts and listens on `localhost:4000`,
  with fast refresh active for any change under the eventual app sources

### Requirement: All ports and credentials are read from `.env` files with committed `.env.example` defaults

The system SHALL read every contributor-tunable port and credential — backend
services, frontend, Postgres, RabbitMQ, reserved Redis slot, orchestrator
paths — from `.env` files. Three `.env.example` files MUST be committed:

- root `.env.example` — orchestrator-level variables
- `apps/backend/.env.example` — backend-stack variables (DB, broker, future
  service ports, reserved Redis port)
- `apps/web/.env.example` — frontend variables (web port, API base URL,
  Node env)

`.env` files MUST be gitignored at every level. Makefiles MUST `-include
.env` and export the variables. `docker-compose.yml` MUST reference
variables with `${VAR}` (no inline literals for ports or credentials) and
MUST supply safe defaults via `${VAR:-default}` where appropriate.

#### Scenario: Contributor changes Postgres port without editing tracked files

- **WHEN** a contributor edits `apps/backend/.env` and sets
  `POSTGRES_PORT=15432` (no edit to `.env.example` or `docker-compose.yml`)
- **THEN** `make dev` brings Postgres up on `localhost:15432` and the
  change does not appear in `git status`

#### Scenario: Missing `.env` does not crash compose

- **WHEN** a contributor forgets to copy `.env.example` to `.env` and runs
  `make dev` in `apps/backend`
- **THEN** Docker Compose still starts using the documented defaults
  declared via `${VAR:-default}` syntax, and the Makefile prints a hint
  pointing at `.env.example`

### Requirement: Each submodule must be independently buildable and deployable without the parent repo

The `apps/backend` and `apps/web` submodules SHALL ship a fully self-contained
build path. A clone of either submodule alone (no parent repo) MUST allow
running `make build` to produce a deployable artefact.

- `apps/backend` MUST ship `Makefile`, `docker-compose.yml`, `Dockerfile`
  (or `Dockerfile.service-template` referenced from compose), `.dockerignore`,
  `.env.example`. `make build` MUST produce Docker images.
- `apps/web` MUST ship `Makefile`, `Dockerfile`, `.dockerignore`,
  `package.json`, `.nvmrc`, `.env.example`. `make build` MUST produce a
  Next.js production build (and, when invoked as `make build-image`, a
  Docker image).
- Neither submodule's Makefile MAY reference paths outside its own working
  tree.

#### Scenario: Standalone backend clone can build deployable images

- **GIVEN** a contributor runs
  `git clone git@github.com:protocyber/akademiq-backend.git`
- **WHEN** they `cd akademiq-backend && cp .env.example .env && make build`
- **THEN** the command exits 0 and produces Docker images, with no
  reference to the parent `akademiq` repo

#### Scenario: Standalone web clone can produce a production build

- **GIVEN** a contributor runs
  `git clone git@github.com:protocyber/akademiq-web.git`
- **WHEN** they `cd akademiq-web && corepack enable && pnpm install && make
  build`
- **THEN** the command exits 0 and produces a Next.js production bundle,
  with no reference to the parent `akademiq` repo

### Requirement: Each submodule Makefile implements the standard target list

Each submodule's `Makefile` SHALL provide the canonical target list per
`docs/internal/13_engineering_standards/12_makefile_standards.md`:

- `make dev` — start the dev loop (definitions above)
- `make migrate` — run database migrations (placeholder today; exits 0
  with a "no migrations yet" notice in `apps/backend`, no-op in
  `apps/web`)
- `make test` — run tests (placeholder today; exits 0 with a notice)
- `make build` — produce build artefacts (Docker images for backend,
  Next.js production bundle for web)
- `make up` — start the compose stack in detached mode (backend) or
  delegate to a placeholder (web; documented as "no compose stack")
- `make down` — stop the compose stack

All targets MUST be defined today. Placeholders MUST exit 0 and MUST print
a one-line note explaining what will fill them in later.

#### Scenario: Every standard target exists today

- **WHEN** a contributor runs each of `make dev`, `make migrate`,
  `make test`, `make build`, `make up`, `make down` in either submodule
- **THEN** each target is defined, prints meaningful output, and exits 0
  (modulo `make dev` which is long-running and exits on Ctrl-C)

### Requirement: Root repo provides convenience wrappers and a `doctor` target

The root `Makefile` SHALL provide thin wrappers and a self-check target.

- `make submodules` — `git submodule update --init --recursive`.
- `make up` / `make down` — delegate to `apps/backend`'s `up` / `down`.
- `make build` / `make test` — run the corresponding target in each
  submodule sequentially.
- `make doctor` — best-effort check of `docker`, `docker compose` (≥ 2.22),
  `node` (matches `.nvmrc`), `pnpm` (via corepack), `git`, `mprocs`
  (advisory), `tmux` (advisory). For each missing tool, print an
  install hint. Exit non-zero only if a *required* tool is missing.

#### Scenario: `make doctor` flags missing required tooling

- **WHEN** a contributor without Docker installed runs `make doctor`
- **THEN** the command prints "docker not found — install Docker Desktop"
  (or similar) and exits non-zero

#### Scenario: `make doctor` notes missing optional tooling without failing

- **WHEN** a contributor with Docker, Node, pnpm, and git but without
  mprocs or tmux runs `make doctor`
- **THEN** the command prints advisory hints for mprocs and tmux but
  exits 0

### Requirement: Local dev stack is documented in architecture spec, root README, and AGENTS.md

The change SHALL update three doc surfaces with the new orchestration story
without expanding scope to other docs.

- `docs/internal/13_engineering_standards/11_devops_local_setup.md` MUST
  describe the `apps/backend/docker-compose.yml` baseline (Postgres 18 +
  RabbitMQ), the `.env` convention, the standard ports, and the
  mprocs/tmux/`-j2` ladder.
- Root `README.md` MUST gain a "Quick start" section covering: clone with
  `--recurse-submodules`, copy three `.env.example` files, install
  prerequisites (Docker Desktop, Node via nvm, `corepack enable`),
  optional `brew install mprocs tmux`, then `make dev`.
- `AGENTS.md` MUST gain a "Local development" subsection enumerating the
  orchestrator targets and the env-file convention.

No other `docs/internal/` file may be edited in this change.

#### Scenario: `11_devops_local_setup.md` reflects the new dev story

- **WHEN** a reader opens
  `docs/internal/13_engineering_standards/11_devops_local_setup.md` after
  this change lands
- **THEN** the file documents the compose stack, the orchestrator commands,
  and the `.env` files

#### Scenario: No unrelated docs are modified

- **WHEN** running `git diff --stat -- docs/internal/` against the parent
  repo branch for this change
- **THEN** the only modified file under `docs/internal/` is
  `13_engineering_standards/11_devops_local_setup.md`
