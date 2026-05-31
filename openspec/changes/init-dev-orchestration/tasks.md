## 1. Preconditions

- [x] 1.1 Confirm Docker Desktop ≥ 4.24 (or Docker Engine + compose plugin v2.22+) is installed; `docker compose version` reports `>= 2.22`
- [x] 1.2 Confirm Node ≥ 20 LTS available via `nvm` and `corepack --version` works (Node ≥ 16.13)
- [x] 1.3 Confirm `git submodule status` shows both `apps/backend` and `apps/web` clean and at upstream `main`
- [x] 1.4 Confirm working tree is clean and we're on a feature branch in the parent repo (not `main`)
- [x] 1.5 Confirm SSH push access to both `protocyber/akademiq-backend` and `protocyber/akademiq-web`
- [x] 1.6 Optional: confirm `mprocs --version` and `tmux -V` are available; if not, proceed (they're advisory)

## 2. Backend submodule scaffolding (commits in `apps/backend`)

- [x] 2.1 In `apps/backend`, create a feature branch `init/dev-makefile-compose` and check it out
- [x] 2.2 Create `apps/backend/.env.example` with documented defaults: `POSTGRES_PORT=5432`, `POSTGRES_USER=akademiq`, `POSTGRES_PASSWORD=akademiq_dev`, `POSTGRES_DB_PREFIX=akademiq`, `RABBITMQ_PORT=5672`, `RABBITMQ_MGMT_PORT=15672`, `RABBITMQ_USER=akademiq`, `RABBITMQ_PASSWORD=akademiq_dev`, reserved `REDIS_PORT=6379` (commented), and commented-out `<SERVICE>_PORT` slots for `IAM`, `BILLING`, `ACADEMIC_CONFIG`, `ACADEMIC_OPS`, `ATTENDANCE`, `GRADING`, `PROMOTION`, `NOTIFICATION` per `docs/internal/06_container_architecture/AcademiQ_Container_Diagram.md`
- [x] 2.3 Append `.env` to `apps/backend/.gitignore` (idempotent — check first)
- [x] 2.4 Create `apps/backend/.dockerignore` covering `target/`, `**/*.rs.bk`, `.env`, `.git`, `node_modules`, `.idea`, `.vscode`, OS noise
- [x] 2.5 Create `apps/backend/docker-compose.yml` with services: `postgres` (image `postgres:18-alpine`, ports `${POSTGRES_PORT:-5432}:5432`, env vars from compose, volume `postgres_data`, healthcheck) and `rabbitmq` (image `rabbitmq:3-management-alpine`, ports `${RABBITMQ_PORT:-5672}:5672` and `${RABBITMQ_MGMT_PORT:-15672}:15672`, env vars, healthcheck)
- [x] 2.6 Add a `networks: { akademiq: { name: akademiq } }` block and join both services to it
- [x] 2.7 Add a commented-out service template inside `docker-compose.yml` showing the canonical `develop.watch` block (build context, action `rebuild`, ignore `target/`) so the next change adding `iam-service` is mechanical
- [x] 2.8 Create `apps/backend/Dockerfile.service-template` (multi-stage Rust build skeleton: builder with `cargo chef` cache pattern, runtime `debian:bookworm-slim`, non-root user, `EXPOSE` placeholder)
- [x] 2.9 Create `apps/backend/Makefile` with targets: `dev` (runs `docker compose --env-file .env up --build --watch`), `up` (`docker compose up -d`), `down` (`docker compose down`), `logs`, `ps`, `migrate` (placeholder echo + exit 0), `test` (placeholder echo + exit 0), `build` (`docker compose build`), `clean` (`docker compose down -v`); use `-include .env` and export variables
- [x] 2.10 Manual verify: `cd apps/backend && cp .env.example .env && make up`, confirm `docker compose ps` shows `postgres` healthy and `rabbitmq` healthy, confirm `psql -h localhost -p $POSTGRES_PORT -U $POSTGRES_USER` connects, confirm RabbitMQ management UI reachable; then `make down && make clean`
- [x] 2.11 Manual verify port customization: edit `.env` to `POSTGRES_PORT=15432`, `make up`, confirm Postgres binds to 15432, `make down`
- [x] 2.12 Update `apps/backend/README.md`: replace the "no scaffold yet" line with a "Local development" section pointing at `make dev` / `make up`; keep the standalone-clone instructions
- [x] 2.13 Commit (`feat: add Makefile, docker-compose, and env template`) and push the branch
- [x] 2.14 Open a PR in `protocyber/akademiq-backend` and merge to `main`; record the resulting `main` SHA for the parent submodule bump (merged as #1; `main` SHA `87e8dd41c48356743cc5f00d9fc2487dd8b5f0aa`)

## 3. Web submodule scaffolding (commits in `apps/web`)

- [x] 3.1 In `apps/web`, create a feature branch `init/dev-makefile` and check it out
- [x] 3.2 Create `apps/web/.nvmrc` pinning Node `20` (or current LTS)
- [x] 3.3 Create `apps/web/.env.example` with `WEB_PORT=3000`, `NEXT_PUBLIC_API_BASE_URL=http://localhost:8080/api/v1`, `NODE_ENV=development`
- [x] 3.4 Append `.env` and `.env.local` to `apps/web/.gitignore` (idempotent)
- [x] 3.5 Create `apps/web/package.json` (minimal): `name`, `version`, `private: true`, `packageManager: "pnpm@<pinned>"` (run `corepack prepare pnpm@latest --activate` first to capture the version), `scripts.dev` placeholder echoing "Next.js scaffold not yet added — placeholder dev server" and exiting 0, `scripts.build`/`scripts.start`/`scripts.lint`/`scripts.test` similar placeholders
- [x] 3.6 Create `apps/web/Dockerfile`: multi-stage `node:20-slim` builder running `pnpm install --frozen-lockfile=false` (lockfile not present yet) + `pnpm build`, runtime stage runs `pnpm start`, exposes `${WEB_PORT}` (use ARG); marked clearly as production-only
- [x] 3.7 Create `apps/web/.dockerignore` covering `node_modules`, `.next`, `out`, `.env*`, `.git`, `.idea`, `.vscode`, OS noise
- [x] 3.8 Create `apps/web/Makefile` with targets: `dev` (corepack enable && pnpm install && pnpm dev — uses `WEB_PORT` from `.env`), `start` (corepack enable && pnpm start), `build` (corepack enable && pnpm build), `build-image` (`docker build`), `test`, `lint`, `up` (alias for `dev` with note), `down` (no-op echo); `-include .env`
- [x] 3.9 Manual verify: `cd apps/web && cp .env.example .env && make dev`, confirm placeholder dev script runs and exits cleanly; verify `make build` placeholder exits 0
- [x] 3.10 Update `apps/web/README.md`: replace "no scaffold yet" line with a "Local development" section pointing at `make dev`; keep standalone-clone instructions
- [x] 3.11 Commit (`feat: add Makefile, Dockerfile, env template, and pnpm config`) and push the branch
- [x] 3.12 Open a PR in `protocyber/akademiq-web` and merge to `main`; record the resulting `main` SHA for the parent submodule bump (merged as #1; `main` SHA `bacb3add7dbc8918a24e53cca78fa670b1d1b9c8`)

## 4. Parent repo orchestrator

- [x] 4.1 Run `git submodule update --remote --merge apps/backend apps/web` to advance the parent's pinned SHAs to the new submodule `main` SHAs from steps 2.14 and 3.12 (then re-bumped backend to `8446e923` after follow-up `fix/dev-watch` PR #2)
- [x] 4.2 Create root `.env.example` with `BACKEND_DIR=apps/backend`, `WEB_DIR=apps/web`, `MPROCS_CONFIG=mprocs.yaml`
- [x] 4.3 Add `.env` to root `.gitignore` (create or append) plus standard noise (`.DS_Store`, `*.swp`)
- [x] 4.4 Create root `mprocs.yaml` with two procs: `backend` (cwd `apps/backend`, cmd `make dev`) and `web` (cwd `apps/web`, cmd `make dev`); set `mouse_scroll_speed: 1`
- [x] 4.5 Create root `Makefile` with targets:
  - `dev` — `mprocs --config mprocs.yaml`; if `mprocs` not on PATH, print error pointing at `make dev-tmux` or `make dev-parallel`
  - `dev-tmux` — start session `akademiq` with two windows (`backend`, `web`) running their `make dev`; reuse existing session if attached
  - `dev-parallel` — `$(MAKE) -j2 dev-backend dev-web`
  - `dev-backend` — `$(MAKE) -C apps/backend dev`
  - `dev-web` — `$(MAKE) -C apps/web dev`
  - `submodules` — `git submodule update --init --recursive`
  - `up` / `down` — delegate to `apps/backend`
  - `build` — `$(MAKE) -C apps/backend build && $(MAKE) -C apps/web build`
  - `test` — `$(MAKE) -C apps/backend test && $(MAKE) -C apps/web test`
  - `doctor` — best-effort check of `docker`, `docker compose` ≥ 2.22, `node` (matches `.nvmrc`), `corepack`, `pnpm`, `git`, advisory `mprocs`, advisory `tmux`; print install hints; exit non-zero only on missing required tools
  - `help` — list all targets with one-line descriptions
- [x] 4.6 Use `-include .env` at the top of root `Makefile` and export variables; mark `.PHONY` for every target
- [x] 4.7 Manual verify: `make submodules` is a no-op on a fully synced tree; `make doctor` exits 0 on a fully provisioned machine and prints actionable hints when a tool is missing (test by temporarily renaming `mprocs` on PATH)
- [x] 4.8 Manual verify: `cp .env.example .env`, `cp apps/backend/.env.example apps/backend/.env`, `cp apps/web/.env.example apps/web/.env`, then `make dev` opens mprocs with two named panes (config parses; mprocs CLI requires a TTY so smoke test was the parallel path — see 4.10)
- [x] 4.9 Manual verify: `make dev-tmux` opens a tmux session named `akademiq` with two windows; detach with `Ctrl-b d`, reattach with `tmux attach -t akademiq`, kill with `tmux kill-session -t akademiq` (verified the create/list/kill flow)
- [x] 4.10 Manual verify: `make dev-parallel` runs both submodule `dev` targets concurrently and exits cleanly on `Ctrl-C` (verified Postgres + RabbitMQ healthy and web placeholder running together; `Ctrl-C` cleanly stops both)

## 5. Documentation

- [x] 5.1 Update root `README.md`: replace any "no scaffold yet" wording with a "Quick start" block listing prerequisites (Docker Desktop ≥ 4.24, Node via nvm, `corepack enable`, optional `brew install mprocs tmux`), the three `cp .env.example .env` steps, and `make dev`
- [x] 5.2 Update `AGENTS.md`: add a "Local development" subsection enumerating root targets (`make dev`, `make dev-tmux`, `make dev-parallel`, `make doctor`, `make submodules`, `make up`, `make down`) and the env-file convention; cross-reference `apps/backend/.env.example` and `apps/web/.env.example`
- [x] 5.3 Update `docs/internal/13_engineering_standards/11_devops_local_setup.md`: extend the file from the current 9-line stub to describe the `apps/backend/docker-compose.yml` baseline (Postgres 18 + RabbitMQ), the standard ports (with a note that the source of truth is `.env.example`), and the mprocs / tmux / `make -j2` ladder; do not change scope
- [x] 5.4 Run `git diff --stat -- docs/internal/` and confirm the only modified file under `docs/internal/` is `13_engineering_standards/11_devops_local_setup.md`
- [x] 5.5 Run `rg -n 'docker[\- ]compose' docs/internal/` and confirm any references still resolve to the new convention

## 6. Validate, commit, push, PR

- [ ] 6.1 Run `openspec validate init-dev-orchestration --strict` and resolve any reported issues
- [ ] 6.2 Run `git submodule status` and confirm both submodules point at the merged `main` SHAs from steps 2.14 and 3.12
- [ ] 6.3 Stage exactly: `Makefile`, `mprocs.yaml`, `.env.example`, `.gitignore`, `README.md`, `AGENTS.md`, `docs/internal/13_engineering_standards/11_devops_local_setup.md`, the submodule pointer bumps, and the openspec change directory; do not stage anything else
- [ ] 6.4 Commit with a message describing the orchestrator and the env-driven dev story (no AI/agent attributions per `AGENTS.md`)
- [ ] 6.5 Push the feature branch and open a PR with `gh pr create`. PR description must include: prereqs, three-step `.env` copy, the `make dev` ladder, and the SSH-only requirement for the submodules
- [ ] 6.6 In a fresh temp directory, `git clone --recurse-submodules <branch URL>` and verify `make doctor` and `make dev` work end-to-end with mprocs
- [ ] 6.7 After review and merge, run `openspec archive init-dev-orchestration` (handled by `/opsx-archive`)

## 7. Rollback (only if needed)

- [ ] 7.1 If the parent PR must be rolled back: revert this PR; submodules retain their Makefiles/Dockerfiles, but the parent loses its orchestrator and `make dev`
- [ ] 7.2 If a submodule PR must be rolled back: revert the submodule PR (or revert just the offending file), then `git submodule update --remote --merge` in the parent and bump the SHA back
- [ ] 7.3 If everything must be undone: revert all three PRs and run `git submodule update --remote --merge` to align the parent's pinned SHAs to the reverted submodule `main`s
