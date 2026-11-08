# Manual-test hub. Run from this folder: `cd scripts/test-hub && make …`.
SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

COMPOSE := docker compose -f compose.yml
# The CLI runs in a throwaway Bun container so the host needs no Bun install.
# -it only when a terminal is attached (password prompts).
TTY := $(shell [ -t 0 ] && echo -it || echo -i)
CLI := docker run --rm $(TTY) -u $(shell id -u):$(shell id -g) -e HUB_PASSWORD \
	-v $(CURDIR):/hub -w /hub -e HUB_CONFIG=/hub/hub.yaml oven/bun:1-alpine bun cli.ts

U    ?=
NAME ?=
ROLE ?= tester

.PHONY: help init up down restart status logs url users user-add passwd user-rm user-disable user-enable check hash backup

help: ## Tampilkan bantuan
	@printf 'Manual-test hub (AkademiQ)\n\n'
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-14s %s\n", $$1, $$2}'
	@printf '\nContoh:\n  make user-add U=fitrah NAME="Fitrah" ROLE=admin\n  make passwd U=fitrah\n'

init: ## Buat hub.yaml dari hub.example.yaml (sekali saja)
	@if [ -f hub.yaml ]; then echo "hub.yaml sudah ada."; else cp hub.example.yaml hub.yaml && chmod 600 hub.yaml && echo "hub.yaml dibuat. Tambah user: make user-add U=<id> NAME=\"Nama\" ROLE=admin"; fi

up: init ## Nyalakan hub (docker compose up -d)
	@mkdir -p ../../docs/manual-tests
	@$(COMPOSE) up -d
	@sleep 1; $(COMPOSE) ps
	@$(MAKE) --no-print-directory url

down: ## Matikan hub (progres tetap aman di volume)
	@$(COMPOSE) down

restart: ## Restart container hub
	@$(COMPOSE) restart

status: ## Status container, user, dan URL
	@$(COMPOSE) ps
	@$(MAKE) --no-print-directory users
	@$(MAKE) --no-print-directory url

logs: ## Ikuti log hub
	@$(COMPOSE) logs -f --tail=100

url: ## Tampilkan URL hub
	@grep -E '^\s+public_url:' hub.yaml 2>/dev/null | sed -E 's/.*:-([^}]*)\}.*/\1/; s/^\s*public_url:\s*//' | sed 's/^/URL: /' || true

users: ## Daftar user di hub.yaml
	@$(CLI) users

user-add: ## Tambah user: U=<id> NAME="Nama" ROLE=admin|tester
	@test -n "$(U)" || { echo "Pakai: make user-add U=<id> NAME=\"Nama\" ROLE=admin|tester"; exit 1; }
	@$(CLI) user-add "$(U)" --name "$(or $(NAME),$(U))" --role "$(ROLE)"

passwd: ## Ganti password: U=<id>
	@test -n "$(U)" || { echo "Pakai: make passwd U=<id>"; exit 1; }
	@$(CLI) passwd "$(U)"

user-rm: ## Hapus user (progres tetap disimpan): U=<id>
	@test -n "$(U)" || { echo "Pakai: make user-rm U=<id>"; exit 1; }
	@$(CLI) user-rm "$(U)"

user-disable: ## Nonaktifkan login user: U=<id>
	@$(CLI) user-disable "$(U)"

user-enable: ## Aktifkan lagi user: U=<id>
	@$(CLI) user-enable "$(U)"

check: ## Validasi hub.yaml
	@$(CLI) check

hash: ## Cetak hash argon2id untuk sebuah password (untuk hub.yaml manual)
	@$(CLI) hash

backup: ## Salin semua progres ke ./backup-<timestamp>.tar.gz
	@ts=$$(date +%Y%m%d-%H%M%S); \
	docker run --rm -v akademiq-test-hub_state:/state:ro -v $(CURDIR):/out alpine tar czf /out/backup-$$ts.tar.gz -C /state progress; \
	echo "backup-$$ts.tar.gz"
