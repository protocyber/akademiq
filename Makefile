# =============================================================================
# AcademiQ — Parent repo orchestrator
# =============================================================================
# This Makefile is the entry point for local development across both
# submodules (apps/backend and apps/web). It DOES NOT replace per-app
# Makefiles — those remain authoritative. The targets here are either
# orchestrator-specific (dev / dev-tmux / dev-parallel / submodules /
# doctor) or thin delegators to the submodule Makefiles.
#
# Standard target list (per docs/internal/13_engineering_standards/12_makefile_standards.md):
#
#   make dev           # primary: launch backend + web together via mprocs
#   make migrate       # delegate to backend (web has no migrations)
#   make seed          # load demo data (delegates to backend)
#   make test          # run tests in both submodules sequentially
#   make test-e2e      # run cross-service backend e2e suite (compose.test.yml)
#   make test-web      # run web Vitest + Playwright suites
#   make build         # build artefacts in both submodules
#   make up            # start backend infra (Postgres + RabbitMQ) detached
#   make down          # stop backend infra (preserves volumes)
#
# Orchestrator extras:
#
#   make dev-host      # backend host loop only (infra in Docker + cargo-watch)
#   make dev-tmux      # tmux fallback for machines without mprocs
#   make dev-parallel  # `make -j2` last-resort fallback
#   make dev-backend   # just the backend dev loop
#   make dev-web       # just the web dev loop
#   make ps            # show status of all services (backend + web)
#   make stop          # kill all host-run service processes (backend + web)
#   make clean         # delete build artefacts in both submodules (keeps volumes)
#   make purge         # DESTRUCTIVE: delete volumes + all artefacts (confirmation required)
#   make submodules    # `git submodule update --init --recursive`
#   make doctor        # check required dev tooling, print install hints
#   make help          # this help screen
#
# Per-machine config lives in `.env` (root, gitignored). Per-app config
# lives in `apps/backend/.env` and `apps/web/.env`.
# =============================================================================

-include .env
export

SHELL := /usr/bin/env bash

BACKEND_DIR ?= apps/backend
WEB_DIR ?= apps/web
MPROCS_CONFIG ?= mprocs.yaml
TMUX_SESSION ?= akademiq

.DEFAULT_GOAL := help
.PHONY: help dev dev-host dev-tmux dev-parallel dev-backend dev-web submodules \
        up down build test test-e2e test-web seed migrate ps stop clean purge doctor

help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# -----------------------------------------------------------------------------
# Dev orchestration ladder: mprocs (primary) → tmux (fallback) → -j2 (last)
# -----------------------------------------------------------------------------

dev: ## Launch backend (host cargo-watch) + web together (mprocs primary)
	@if ! command -v mprocs >/dev/null; then \
		echo ">> mprocs not found on PATH."; \
		echo ">>   Install:  brew install mprocs   (or  cargo install mprocs)"; \
		echo ">>   Or fall back to:"; \
		echo ">>     make dev-tmux       # tmux fallback"; \
		echo ">>     make dev-parallel   # plain make -j2 fallback"; \
		exit 1; \
	fi
	$(MAKE) -C $(BACKEND_DIR) up
	@set -a; \
	[ -f $(BACKEND_DIR)/.env ] && source $(BACKEND_DIR)/.env; \
	pg="postgres://$${POSTGRES_USER:-akademiq}:$${POSTGRES_PASSWORD:-akademiq_dev}@127.0.0.1:$${POSTGRES_PORT:-5432}"; \
	export IAM_DATABASE_URL="$$pg/iam_db"; \
	export BILLING_DATABASE_URL="$$pg/billing_db"; \
	export ACADEMIC_CONFIG_DATABASE_URL="$$pg/academic_config_db"; \
	export ACADEMIC_OPS_DATABASE_URL="$$pg/academic_ops_db"; \
	export GRADING_DATABASE_URL="$$pg/grading_db"; \
	export RABBITMQ_URL="amqp://$${RABBITMQ_USER:-akademiq}:$${RABBITMQ_PASSWORD:-akademiq_dev}@127.0.0.1:$${RABBITMQ_PORT:-5672}"; \
	export IAM_BASE_URL="http://127.0.0.1:$${IAM_PORT:-8081}"; \
	export FEATURES_TOML_PATH="features.toml"; \
	export RUSTFLAGS="-Clink-arg=-fuse-ld=mold"; \
	export CARGO_BUILD_JOBS="$${CARGO_BUILD_JOBS:-4}"; \
	set +a; \
	mprocs --config $(MPROCS_CONFIG)

dev-host: ## Run only the backend host loop (infra in Docker + cargo-watch)
	$(MAKE) -C $(BACKEND_DIR) dev-host

dev-tmux: ## Launch backend + web in a tmux session (fallback for no mprocs)
	@if ! command -v tmux >/dev/null; then \
		echo ">> tmux not found on PATH."; \
		echo ">>   Install:  brew install tmux"; \
		echo ">>   Or fall back to:  make dev-parallel"; \
		exit 1; \
	fi
	@if tmux has-session -t $(TMUX_SESSION) 2>/dev/null; then \
		echo ">> Session '$(TMUX_SESSION)' already exists — attaching."; \
		tmux attach -t $(TMUX_SESSION); \
	else \
		echo ">> Starting tmux session '$(TMUX_SESSION)' (detach: Ctrl-b d)"; \
		tmux new-session -d -s $(TMUX_SESSION) -n backend -c $(BACKEND_DIR) 'make dev'; \
		tmux new-window -t $(TMUX_SESSION) -n web -c $(WEB_DIR) 'make dev'; \
		tmux attach -t $(TMUX_SESSION); \
	fi

dev-parallel: ## Launch backend + web with `make -j2` (last-resort fallback)
	$(MAKE) -j2 dev-backend dev-web

dev-backend: ## Run only the backend dev loop
	$(MAKE) -C $(BACKEND_DIR) dev

dev-web: ## Run only the web dev loop
	$(MAKE) -C $(WEB_DIR) dev

# -----------------------------------------------------------------------------
# Submodule + lifecycle helpers
# -----------------------------------------------------------------------------

submodules: ## Initialise / update submodules
	git submodule update --init --recursive

up: ## Start backend infra (Postgres + RabbitMQ) detached
	$(MAKE) -C $(BACKEND_DIR) up

down: ## Stop backend infra
	$(MAKE) -C $(BACKEND_DIR) down

build: ## Build artefacts for both submodules (SLOW)
	@bash scripts/confirm.sh "make build" "builds the backend release Docker images (~8 min cold) AND the web bundle. For the daily loop use 'make dev'."
	YES=1 $(MAKE) -C $(BACKEND_DIR) build
	$(MAKE) -C $(WEB_DIR) build

test: ## Run tests in both submodules (SLOW)
	@bash scripts/confirm.sh "make test" "compiles and runs the FULL backend + web test suites — several minutes. For a quick check run 'cargo test' in apps/backend."
	$(MAKE) -C $(BACKEND_DIR) test
	$(MAKE) -C $(WEB_DIR) test

test-e2e: ## Run cross-service backend e2e suite (compose.test.yml) (SLOW)
	@bash scripts/confirm.sh "make test-e2e" "builds the compose.test.yml stack and runs the cross-service suite — several minutes."
	YES=1 $(MAKE) -C $(BACKEND_DIR) test-e2e

test-web: ## Run web Vitest + Playwright suites (SLOW)
	@bash scripts/confirm.sh "make test-web" "runs Vitest + Playwright (may download browsers) — several minutes."
	$(MAKE) -C $(WEB_DIR) test

seed: ## Load demo data (plans + tenants) into the local stack (SLOW)
	@bash scripts/confirm.sh "make seed" "builds the seed image and starts the stack — a few minutes on a cold cache."
	YES=1 $(MAKE) -C $(BACKEND_DIR) seed

migrate: ## Run database migrations (backend only)
	$(MAKE) -C $(BACKEND_DIR) migrate

ps: ## Show status of all services (backend compose + web dev server)
	@echo ">>> backend"
	@$(MAKE) -C $(BACKEND_DIR) ps
	@echo ""
	@echo ">>> web"
	@$(MAKE) -C $(WEB_DIR) ps

stop: ## Kill all host-run service processes (backend + web dev server)
	@echo ">>> backend"
	@$(MAKE) -C $(BACKEND_DIR) stop
	@echo ""
	@echo ">>> web"
	@$(MAKE) -C $(WEB_DIR) stop

clean: ## Delete build artefacts in both submodules (SLOW next build)
	@bash scripts/confirm.sh "make clean" "deletes the ~9.5 GB backend target/ and web artefacts; the NEXT build will be a full cold rebuild."
	@echo ">>> backend"
	@YES=1 $(MAKE) -C $(BACKEND_DIR) clean
	@echo ""
	@echo ">>> web"
	@$(MAKE) -C $(WEB_DIR) clean

purge: ## DESTRUCTIVE: delete volumes + all build artefacts (requires confirmation)
	@bash scripts/purge.sh

doctor: ## Check required dev tooling, print install hints
	@bash scripts/doctor.sh
