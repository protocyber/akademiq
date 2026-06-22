#!/usr/bin/env bash
# =============================================================================
# AcademiQ — RabbitMQ local purge (full reset)
# =============================================================================
# Wipes ALL data from the local RabbitMQ broker: queues, exchanges, messages,
# bindings. Use this every time you switch the backend DB context (local
# Postgres ↔ dev Supabase) to prevent stale events from cross-contaminating
# projection tables across databases.
#
# Method: rabbitmqctl stop_app → reset → start_app
#   - Wipes mnesia data (queues, exchanges, bindings, messages)
#   - Keeps the administrative user (set via RABBITMQ_DEFAULT_USER/PASS env at
#     container start, not persisted in mnesia)
#   - Services re-create exchange + queues automatically on reconnect
#     (all topology is declared durable with auto-declare in outbox.rs/events.rs)
#
# Usage:
#   ./scripts/rabbitmq-purge.sh             # prompt y/N before reset
#   ./scripts/rabbitmq-purge.sh --yes       # skip prompt (non-interactive)
#   ./scripts/rabbitmq-purge.sh --help
#
# Exit codes:
#   0  reset successful
#   1  container not found / not running / reset failed / bad args
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

ASSUME_YES=0

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
    *) echo "ERROR: unknown argument: $1 (try --help)" >&2; exit 1 ;;
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

# ---------------------------------------------------------------------------
# Locate the RabbitMQ container
# ---------------------------------------------------------------------------
section "Locating RabbitMQ container"

CONTAINER=""

# Method 1: docker compose service lookup (most reliable)
BACKEND_DIR="${BACKEND_DIR:-apps/backend}"
if [ -f "$BACKEND_DIR/docker-compose.yml" ]; then
  CONTAINER="$(docker compose -f "$BACKEND_DIR/docker-compose.yml" ps -q rabbitmq 2>/dev/null || true)"
  if [ -n "$CONTAINER" ]; then
    # Resolve the short ID to a name for display
    CONTAINER_NAME="$(docker inspect --format '{{.Name}}' "$CONTAINER" 2>/dev/null | sed 's|^/||' || echo "$CONTAINER")"
  fi
fi

# Method 2: fall back to the known container name
if [ -z "$CONTAINER" ]; then
  for name in akademiq-rabbitmq akademiq_backend-rabbitmq-1 akademiq-backend-rabbitmq-1; do
    if docker inspect "$name" >/dev/null 2>&1; then
      CONTAINER="$name"
      CONTAINER_NAME="$name"
      break
    fi
  done
fi

# Method 3: last resort — any running container whose image is rabbitmq
if [ -z "$CONTAINER" ]; then
  CONTAINER="$(docker ps --filter 'ancestor=rabbitmq:3-management-alpine' -q 2>/dev/null | head -n1 || true)"
  if [ -n "$CONTAINER" ]; then
    CONTAINER_NAME="$(docker inspect --format '{{.Name}}' "$CONTAINER" 2>/dev/null | sed 's|^/||' || echo "$CONTAINER")"
    warn "Using loosely-matched container: $CONTAINER_NAME"
  fi
fi

if [ -z "$CONTAINER" ]; then
  err "No running RabbitMQ container found."
  echo    "  Start the local stack first:" >&2
  echo    "    make up" >&2
  echo    "  Or check Docker is running." >&2
  exit 1
fi

ok "Found container: $CONTAINER_NAME"

# Verify rabbitmqctl exists inside the container. The path differs by image
# variant: rabbitmq:3-management uses /usr/local/bin, rabbitmq:3-management-alpine
# uses /opt/rabbitmq/sbin. `command -v` resolves it from PATH.
if ! docker exec "$CONTAINER" sh -c 'command -v rabbitmqctl >/dev/null 2>&1'; then
  err "rabbitmqctl not found inside container '$CONTAINER_NAME'."
  err "  Is this actually a rabbitmq image?"
  exit 1
fi

# ---------------------------------------------------------------------------
# Show BEFORE state
# ---------------------------------------------------------------------------
section "Broker state (before reset)"

BEFORE_QUEUES="$(docker exec "$CONTAINER" rabbitmqctl list_queues name messages --no-table-headers 2>/dev/null \
  | grep -vE '^(Timeout:|Listing queues)' || true)"
if [ -z "$BEFORE_QUEUES" ]; then
  log "No queues defined (broker already empty or freshly started)."
else
  log "Current queues:"
  printf "%s\n" "$BEFORE_QUEUES" | while IFS= read -r line; do
    [ -n "$line" ] && printf "    %s\n" "$line"
  done
fi

BEFORE_EXCHANGES="$(docker exec "$CONTAINER" rabbitmqctl list_exchanges name --no-table-headers 2>/dev/null | grep -E '^akademiq\.' || true)"
if [ -n "$BEFORE_EXCHANGES" ]; then
  log "AkademiQ exchanges:"
  printf "%s\n" "$BEFORE_EXCHANGES" | while IFS= read -r line; do
    [ -n "$line" ] && printf "    %s\n" "$line"
  done
fi

# ---------------------------------------------------------------------------
# Confirm
# ---------------------------------------------------------------------------
section "Confirm full reset"

printf "${YELLOW}[WARN]${RESET} ${BOLD}This will WIPE ALL data${RESET} from RabbitMQ '%s':\n" "$CONTAINER_NAME"
echo   "  - All queues and their messages"
echo   "  - All exchanges and bindings"
echo   "  - Services will re-create topology on reconnect"
echo   ""
if [ "$ASSUME_YES" -eq 0 ]; then
  if [ ! -t 0 ]; then
    err "Not a TTY and --yes not given. Aborting to avoid accidental reset."
    exit 1
  fi
  printf "Proceed with full reset? ${BOLD}[y/N]${RESET} "
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
else
  log "--yes given, skipping prompt."
fi

# ---------------------------------------------------------------------------
# Execute reset
# ---------------------------------------------------------------------------
section "Resetting RabbitMQ"

log "Stopping RabbitMQ app..."
docker exec "$CONTAINER" rabbitmqctl stop_app

log "Resetting (wiping all mnesia data)..."
docker exec "$CONTAINER" rabbitmqctl reset

log "Starting RabbitMQ app..."
docker exec "$CONTAINER" rabbitmqctl start_app

ok "Reset complete."

# ---------------------------------------------------------------------------
# Show AFTER state
# ---------------------------------------------------------------------------
section "Broker state (after reset)"

AFTER_QUEUES="$(docker exec "$CONTAINER" rabbitmqctl list_queues name messages --no-table-headers 2>/dev/null \
  | grep -vE '^(Timeout:|Listing queues)' || true)"
if [ -z "$AFTER_QUEUES" ]; then
  ok "No queues — broker is clean."
else
  log "Queues present:"
  printf "%s\n" "$AFTER_QUEUES" | while IFS= read -r line; do
    [ -n "$line" ] && printf "    %s\n" "$line"
  done
fi

echo ""
log "Exchange + queues will be re-created automatically when services reconnect."
log "Restart your backend services to trigger re-declaration."
