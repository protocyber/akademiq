#!/usr/bin/env bash
# =============================================================================
# AcademiQ — DB context switcher
# =============================================================================
# Orchestrates switching the backend database context between local Postgres
# and the dev Supabase project, while keeping RabbitMQ local.
#
# Switching flow:
#   1. Stop all running backend services (kill host cargo processes)
#   2. Ensure local infra is up (Postgres + RabbitMQ)
#   3. Full-reset RabbitMQ to purge stale events (prevents cross-DB pollution)
#   4. Print the env file to load + the exact command to start services
#
# This script does NOT auto-start services. You run the printed command
# yourself so you keep full control over mprocs / tmux / cargo-watch.
#
# Why purge the broker on every switch?
#   The outbox publisher drains events from the DB's outbox table into local
#   RabbitMQ. Consumer services (grading, academic-ops, academic-config) read
#   from durable queues and upsert into projection tables with NO event_id
#   dedup. If you switch the DATABASE_URL without purging, stale messages
#   from the previous DB context will be applied to the new DB's projections,
#   silently corrupting data with orphan UUIDs.
#
# Usage:
#   ./scripts/db-switch.sh local              # switch to local Postgres
#   ./scripts/db-switch.sh dev-supabase       # switch to dev Supabase
#   ./scripts/db-switch.sh <target> --yes     # skip confirmation prompt
#   ./scripts/db-switch.sh --help
#
# Exit codes:
#   0  switch completed (broker purged, ready to start services)
#   1  bad target / missing env file / pre-flight failure
#   2  purge failed (services may be stopped — check broker manually)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

ASSUME_YES=0
TARGET=""

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
usage() {
  sed -n '3,${ /^#/!q; s/^# \?//; p; }' "$0"
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)  ASSUME_YES=1; shift ;;
    --help|-h) usage ;;
    -*)
      echo "ERROR: unknown flag: $1 (try --help)" >&2; exit 1 ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$1"; shift
      else
        echo "ERROR: unexpected extra argument: $1" >&2; exit 1
      fi ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf "${BLUE}[INFO]${RESET} %s\n" "$*"; }
ok()   { printf "${GREEN}[ OK ]${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${RESET} %s\n" "$*"; }
err()  { printf "${RED}[ERR ]${RESET} %s\n" "$*" >&2; }
section() { printf "\n${BOLD}${BLUE}━━━ %s ━━━${RESET}\n" "$*"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="${BACKEND_DIR:-$REPO_ROOT/apps/backend}"
SCRIPTS_DIR="$REPO_ROOT/scripts"

# ---------------------------------------------------------------------------
# Resolve target → env file
# ---------------------------------------------------------------------------
case "$TARGET" in
  local)
    ENV_FILE="$BACKEND_DIR/.env"
    ENV_DESC="local Postgres (schema-per-service)"
    NEXT_TARGET="dev-supabase"
    ;;
  dev-supabase)
    ENV_FILE="$BACKEND_DIR/.env.dev-supabase"
    ENV_DESC="dev Supabase (schema-per-service)"
    NEXT_TARGET="local"
    ;;
  "")
    err "No target specified."
    echo    "" >&2
    echo    "Usage:" >&2
    echo    "  ./scripts/db-switch.sh local         # local Postgres" >&2
    echo    "  ./scripts/db-switch.sh dev-supabase  # dev Supabase" >&2
    echo    "  make db-switch TARGET=dev-supabase" >&2
    exit 1
    ;;
  *)
    err "Unknown target: '$TARGET'"
    echo    "Valid targets: local | dev-supabase" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Validate env file exists
# ---------------------------------------------------------------------------
if [ ! -f "$ENV_FILE" ]; then
  err "Env file not found: $ENV_FILE"
  case "$TARGET" in
    local)
      echo "  Create it from the example:" >&2
      echo "    cp $BACKEND_DIR/.env.example $ENV_FILE" >&2 ;;
    dev-supabase)
      echo "  Create it from the example:" >&2
      echo "    cp $BACKEND_DIR/.env.dev-supabase.example $ENV_FILE" >&2
      echo "  Then fill in your dev Supabase project-ref + password." >&2 ;;
  esac
  exit 1
fi

# Quick check: does the env file actually set DATABASE_URL for at least one
# service? (catches an empty or placeholder file)
iam_url="$(grep -E '^IAM_DATABASE_URL=' "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
if [ -z "$iam_url" ]; then
  err "Env file '$ENV_FILE' does not set IAM_DATABASE_URL."
  err "  It looks empty or malformed. Check the file contents."
  exit 1
fi

# ---------------------------------------------------------------------------
# Show plan + confirm
# ---------------------------------------------------------------------------
section "DB context switch"

printf "  ${BOLD}Target${RESET}:  %s (%s)\n" "$TARGET" "$ENV_DESC"
printf "  ${BOLD}Env${RESET}:     %s\n" "$ENV_FILE"
echo   ""
echo   "This will:"
echo   "  1. Stop all running backend services (kill cargo processes)"
echo   "  2. Ensure local infra is up (make up)"
echo   "  3. Full-reset RabbitMQ (purge all stale events)"
echo   "  4. Print the command to start services with the new env"
echo   ""

if [ "$ASSUME_YES" -eq 0 ]; then
  if [ ! -t 0 ]; then
    err "Not a TTY and --yes not given. Aborting to avoid accidental switch."
    exit 1
  fi
  printf "Proceed? ${BOLD}[y/N]${RESET} "
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

# ---------------------------------------------------------------------------
# Step 1: Stop services
# ---------------------------------------------------------------------------
section "Step 1/3 — Stop backend services"

# The backend Makefile's stop target only covers iam + billing. Kill all 5
# service binaries plus cargo-watch/mprocs to be safe, ignoring failures.
stopped_any=0
for svc in iam-service billing-service academic-config-service academic-ops-service grading-service; do
  if pgrep -f "[t]arget/.*/${svc}" >/dev/null 2>&1; then
    pkill -TERM -f "[t]arget/.*/${svc}" 2>/dev/null || true
    log "  Stopped: $svc"
    stopped_any=1
  fi
done

if [ "$stopped_any" -eq 0 ]; then
  log "  No host-run service binaries found running."
else
  # Give processes a moment to exit cleanly
  sleep 2
  # Force-kill any stragglers
  for svc in iam-service billing-service academic-config-service academic-ops-service grading-service; do
    pgrep -f "[t]arget/.*/${svc}" >/dev/null 2>&1 && pkill -KILL -f "[t]arget/.*/${svc}" 2>/dev/null || true
  done
fi

ok "All backend services stopped."

# ---------------------------------------------------------------------------
# Step 2: Ensure infra up
# ---------------------------------------------------------------------------
section "Step 2/3 — Ensure local infra is up"

if [ ! -f "$BACKEND_DIR/Makefile" ]; then
  err "Backend Makefile not found: $BACKEND_DIR/Makefile"
  exit 1
fi

log "Starting Postgres + RabbitMQ (if not already running)..."
if ! make -C "$BACKEND_DIR" up >/dev/null 2>&1; then
  warn "make up returned non-zero. Infra may already be running or there was an error."
  warn "Check with: make -C $BACKEND_DIR ps"
fi
ok "Infra is up."

# ---------------------------------------------------------------------------
# Step 3: Purge RabbitMQ
# ---------------------------------------------------------------------------
section "Step 3/3 — Purge RabbitMQ (full reset)"

if [ ! -x "$SCRIPTS_DIR/rabbitmq-purge.sh" ]; then
  err "rabbitmq-purge.sh not found or not executable: $SCRIPTS_DIR/rabbitmq-purge.sh"
  exit 2
fi

if ! "$SCRIPTS_DIR/rabbitmq-purge.sh" --yes; then
  err "RabbitMQ purge failed. Services are stopped; broker may be in an inconsistent state."
  err "  Inspect manually: docker exec akademiq-rabbitmq rabbitmqctl status"
  exit 2
fi

ok "RabbitMQ purged."

# ---------------------------------------------------------------------------
# Done — print start instructions
# ---------------------------------------------------------------------------
section "Ready: $TARGET"

printf "${GREEN}[ OK ]${RESET} DB context switched to: ${BOLD}%s${RESET} (%s)\n" "$TARGET" "$ENV_DESC"

# Extract DB URLs from the env file, mask passwords for display
echo ""
log "Active database URLs (from $ENV_FILE):"
for var in IAM_DATABASE_URL BILLING_DATABASE_URL ACADEMIC_CONFIG_DATABASE_URL ACADEMIC_OPS_DATABASE_URL GRADING_DATABASE_URL; do
  url="$(grep -E "^${var}=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  if [ -n "$url" ]; then
    masked="$(printf '%s' "$url" | sed -E 's|(://[^:]+:)[^@]+(@)|\1***\2|')"
    printf "    %-22s %s\n" "$var" "$masked"
  fi
done

echo ""
printf "${BLUE}[INFO]${RESET} RabbitMQ: ${BOLD}local${RESET} (freshly purged — no stale events)\n"
echo ""
section "Next: start services"
echo ""
if [ "$TARGET" = "dev-supabase" ]; then
  printf "  ${BOLD}cd${RESET} %s\n" "$REPO_ROOT"
  printf "  ${BOLD}make dev-supabase${RESET}\n"
else
  printf "  ${BOLD}cd${RESET} %s\n" "$REPO_ROOT"
  printf "  ${BOLD}make dev${RESET}\n"
fi
echo ""
echo "Services will re-create RabbitMQ exchange + queues on boot (auto-declare)."
echo ""
printf "To switch back: ${BOLD}make db-switch TARGET=%s${RESET}\n" "$NEXT_TARGET"
