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
#   make test          # run tests in both submodules sequentially
#   make build         # build artefacts in both submodules
#   make up            # start backend infra (Postgres + RabbitMQ) detached
#   make down          # stop backend infra
#
# Orchestrator extras:
#
#   make dev-tmux      # tmux fallback for machines without mprocs
#   make dev-parallel  # `make -j2` last-resort fallback
#   make dev-backend   # just the backend dev loop
#   make dev-web       # just the web dev loop
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
.PHONY: help dev dev-tmux dev-parallel dev-backend dev-web submodules \
        up down build test migrate doctor

help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# -----------------------------------------------------------------------------
# Dev orchestration ladder: mprocs (primary) → tmux (fallback) → -j2 (last)
# -----------------------------------------------------------------------------

dev: ## Launch backend + web together (mprocs primary)
	@if ! command -v mprocs >/dev/null; then \
		echo ">> mprocs not found on PATH."; \
		echo ">>   Install:  brew install mprocs   (or  cargo install mprocs)"; \
		echo ">>   Or fall back to:"; \
		echo ">>     make dev-tmux       # tmux fallback"; \
		echo ">>     make dev-parallel   # plain make -j2 fallback"; \
		exit 1; \
	fi
	mprocs --config $(MPROCS_CONFIG)

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

build: ## Build artefacts for both submodules
	$(MAKE) -C $(BACKEND_DIR) build
	$(MAKE) -C $(WEB_DIR) build

test: ## Run tests in both submodules
	$(MAKE) -C $(BACKEND_DIR) test
	$(MAKE) -C $(WEB_DIR) test

migrate: ## Run database migrations (backend only)
	$(MAKE) -C $(BACKEND_DIR) migrate

# -----------------------------------------------------------------------------
# Doctor: best-effort tooling check
# -----------------------------------------------------------------------------

doctor: ## Check required dev tooling, print install hints
	@bash -eu -c '\
	  fail=0; \
	  check_required() { \
	    local label="$$1"; local cmd="$$2"; local hint="$$3"; \
	    if command -v "$$cmd" >/dev/null 2>&1; then \
	      printf "  \033[32m✓\033[0m %s\n" "$$label"; \
	    else \
	      printf "  \033[31m✗\033[0m %s — missing. %s\n" "$$label" "$$hint"; \
	      fail=1; \
	    fi; \
	  }; \
	  check_optional() { \
	    local label="$$1"; local cmd="$$2"; local hint="$$3"; \
	    if command -v "$$cmd" >/dev/null 2>&1; then \
	      printf "  \033[32m✓\033[0m %s\n" "$$label"; \
	    else \
	      printf "  \033[33m·\033[0m %s — optional, not found. %s\n" "$$label" "$$hint"; \
	    fi; \
	  }; \
	  echo "Required tooling:"; \
	  check_required "git"            "git"     "Install via your OS package manager."; \
	  check_required "docker"         "docker"  "Install Docker Desktop >= 4.24 (https://www.docker.com/)."; \
	  if command -v docker >/dev/null 2>&1; then \
	    cv=$$(docker compose version --short 2>/dev/null || echo 0.0.0); \
	    if [ "$$(printf "2.22.0\n%s\n" "$$cv" | sort -V | head -n1)" = "2.22.0" ]; then \
	      printf "  \033[32m✓\033[0m docker compose plugin (%s) >= 2.22\n" "$$cv"; \
	    else \
	      printf "  \033[31m✗\033[0m docker compose plugin too old (%s) — need >= 2.22 for compose --watch.\n" "$$cv"; \
	      fail=1; \
	    fi; \
	  fi; \
	  check_required "node"           "node"    "Install Node 20 LTS via nvm (https://github.com/nvm-sh/nvm)."; \
	  check_required "corepack"       "corepack" "Run: corepack enable (bundled with Node >= 16.13)."; \
	  if command -v node >/dev/null 2>&1; then \
	    nv=$$(node --version | sed s/^v//); \
	    if [ "$$(printf "20.0.0\n%s\n" "$$nv" | sort -V | head -n1)" = "20.0.0" ]; then \
	      printf "  \033[32m✓\033[0m node (%s) >= 20\n" "$$nv"; \
	    else \
	      printf "  \033[33m·\033[0m node version (%s) is below 20 LTS — nvm use should pick up apps/web/.nvmrc.\n" "$$nv"; \
	    fi; \
	  fi; \
	  echo ""; \
	  echo "Optional tooling:"; \
	  check_optional "mprocs (primary, used by make dev)" "mprocs" "brew install mprocs   (or  cargo install mprocs)"; \
	  check_optional "tmux (used by make dev-tmux)"       "tmux"   "brew install tmux"; \
	  echo ""; \
	  echo ".env files:"; \
	  for f in .env $(BACKEND_DIR)/.env $(WEB_DIR)/.env; do \
	    if [ -f "$$f" ]; then \
	      printf "  \033[32m✓\033[0m %s\n" "$$f"; \
	    else \
	      printf "  \033[33m·\033[0m %s missing — run: cp %s.example %s\n" "$$f" "$$f" "$$f"; \
	    fi; \
	  done; \
	  echo ""; \
	  if [ $$fail -ne 0 ]; then \
	    echo "Doctor: required tools missing. Fix the items marked ✗ above."; \
	    exit 1; \
	  else \
	    echo "Doctor: all required tools present."; \
	  fi; \
	'
