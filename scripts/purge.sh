#!/usr/bin/env bash
# =============================================================================
# AkademiQ — root purge
# =============================================================================
# DESTRUCTIVE: stops all services, deletes Docker volumes, Cargo build
# artefacts, .next/, and node_modules/.
#
# Usage: bash scripts/purge.sh [--yes]
#   --yes   skip the interactive prompt (for CI / scripted use)
#
# Called by: make purge (root repo)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
RESET='\033[0m'

BACKEND_DIR="${BACKEND_DIR:-apps/backend}"
WEB_DIR="${WEB_DIR:-apps/web}"
SKIP_PROMPT="${1:-}"

if [ "$SKIP_PROMPT" != "--yes" ]; then
  printf "${RED}\n"
  echo "  ╔══════════════════════════════════════════════════════════════╗"
  echo "  ║  WARNING: purge will permanently DELETE:                     ║"
  echo "  ║    • postgres + rabbitmq Docker volumes (all local data)     ║"
  echo "  ║    • Cargo target/ directory                                 ║"
  echo "  ║    • .next/ and node_modules/                                ║"
  echo "  ║  Run 'make up && make migrate && make seed' to restore data. ║"
  echo "  ╚══════════════════════════════════════════════════════════════╝"
  printf "${RESET}\n"
  printf "  Type 'yes' to continue, anything else to abort: "
  read -r ans
  if [ "$ans" != "yes" ]; then
    echo ">> aborted."
    exit 0
  fi
fi

echo ">> stopping compose stack..."
docker compose -p akademiq --env-file "${BACKEND_DIR}/.env" -f "${BACKEND_DIR}/docker-compose.yml" down 2>/dev/null || true

echo ">> deleting Docker volumes..."
docker volume rm akademiq_postgres_data akademiq_rabbitmq_data 2>/dev/null || true

echo ">> deleting Cargo build artefacts..."
(cd "${BACKEND_DIR}" && cargo clean) 2>/dev/null || true

echo ">> deleting web build artefacts and node_modules..."
rm -rf "${WEB_DIR}/.next" "${WEB_DIR}/node_modules"

echo ">> purge complete."
echo "   Run 'make up && make migrate && make seed' to restore demo data."
echo "   Run 'cd ${WEB_DIR} && pnpm install' to restore node_modules."
